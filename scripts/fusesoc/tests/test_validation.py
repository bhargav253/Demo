# SPDX-License-Identifier: Apache-2.0
"""Validation semantics and real bounded-process failure-path checks."""
import copy
import json
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from types import SimpleNamespace
import yaml

from fusesoc.validation.model import expand, validate, sha, validate_parameters
from fusesoc.validation.engine import assess, execute_job, merge_coverage
from fusesoc.validation.execution import run
from fusesoc.validation.report import render, save

ROOT=Path(__file__).resolve().parents[3]
CONFIG=yaml.safe_load((ROOT/'ip/core/riscv.core').read_text().split('\n',1)[1])


class SchemaTests(unittest.TestCase):
    def test_health_membership_and_inputs(self):
        cfg=CONFIG['validation']
        validate(cfg,CONFIG['targets'])
        jobs=expand(ROOT,cfg,'health')
        self.assertEqual(len(jobs),97)
        self.assertEqual(sum(j['run_mode']=='wait3' for j in jobs),47)
        self.assertEqual(jobs,expand(ROOT,cfg,'health'))
        self.assertEqual(len({j['id'] for j in jobs}),97)
        validate_parameters(SimpleNamespace(_capi_data=CONFIG),cfg,jobs)

    def test_unknown_field_and_references(self):
        for field,value in [('bad_field',{}),('version',2)]:
            cfg=copy.deepcopy(CONFIG['validation']);cfg[field]=value
            with self.assertRaises(ValueError):validate(cfg,CONFIG['targets'])
        cfg=copy.deepcopy(CONFIG['validation']);cfg['tests']['boot']['build_mode']='missing'
        with self.assertRaises(ValueError):validate(cfg,CONFIG['targets'])

    def test_unknown_suite_or_test(self):
        for suite,test in [('missing',None),('health','act4/does-not-exist')]:
            with self.assertRaises(ValueError):expand(ROOT,CONFIG['validation'],suite,test)

    def test_runtime_does_not_change_build(self):
        cfg=CONFIG['validation']
        a=expand(ROOT,cfg,'health',test='act4/I-add-00',seed=1)
        b=expand(ROOT,cfg,'health',test='act4/I-add-00',seed=42,run_mode='wait3')
        self.assertEqual(a[0]['build_mode'],b[0]['build_mode'])
        self.assertNotEqual(a[0]['parameters'],b[0]['parameters'])

    def test_manifest_checksum_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);(root/'bad.elf').write_bytes(b'changed')
            (root/'manifest.json').write_text(json.dumps({'tests':[{'file':'bad.elf','sha256':'0'*64}]}))
            cfg=copy.deepcopy(CONFIG['validation']);cfg['tests']['act4']['manifest']='manifest.json'
            with self.assertRaisesRegex(ValueError,'checksum'):expand(root,cfg,'health',test='act4')

    def test_runtime_compile_parameter_confusion(self):
        jobs=expand(ROOT,CONFIG['validation'],'health',test='boot')
        jobs[0]['parameters']['UNDECLARED']=7
        with self.assertRaises(ValueError):validate_parameters(SimpleNamespace(_capi_data=CONFIG),CONFIG['validation'],jobs)


class ExecutionTests(unittest.TestCase):
    def execute(self,code,timeout=2,max_log=4096,cancel=None):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)
            result=run([sys.executable,'-c',code],path,path/'log',timeout,max_log,4096,cancel or threading.Event())
            return result,(path/'log').read_text()

    def test_silent_timeout_and_descendants(self):
        result,_=self.execute('import subprocess,sys;subprocess.Popen([sys.executable,"-c","import time;time.sleep(60)"])',timeout=.2)
        self.assertEqual(result['status'],'TIMEOUT')
        self.assertEqual(result['exit_status'],124)

    def test_cancel(self):
        event=threading.Event();timer=threading.Timer(.1,event.set);timer.start()
        try: result,_=self.execute('import time;time.sleep(60)',cancel=event)
        finally:timer.join()
        self.assertEqual(result['status'],'CANCELLED')

    def test_output_limit(self):
        result,text=self.execute('import os;os.write(1,b"x"*100000)')
        self.assertEqual(result['status'],'OUTPUT_LIMIT');self.assertLess(len(text),4200)

    def test_file_limit(self):
        result,_=self.execute('open("wave.fst","wb").write(b"x"*100000)')
        self.assertEqual(result['status'],'FAIL')

    def test_zero_exit_needs_pass_and_no_fail(self):
        build={'pass_pattern':'PASS','fail_pattern':'FAIL'}
        for text in ('finished','PASS\nFAIL'):
            self.assertEqual(assess({'status':'PASS'},text,build)['status'],'FAIL')
        self.assertEqual(assess({'status':'PASS'},'PASS',build)['status'],'PASS')

    def test_missing_coverage_fails_job(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);exe=root/'simulator'
            exe.write_text('#!/bin/sh\necho PASS\n');exe.chmod(0o755)
            job={'id':'job-1','test':'fake','parameters':{},'seed':1,'run_mode':'base','elf':None}
            build={'pass_pattern':'PASS','coverage_arg':'COVERAGE'}
            policy={'timeout':2,'max_log_mib':1,'max_wave_mib':1}
            result=execute_job(job,build,exe,root/'run',policy,threading.Event(),root,'axon:test:fake:1','config')
            self.assertEqual(result['status'],'FAIL')
            self.assertIn('no coverage',result['reason'])

    def test_merge_rejects_incompatible_builds_before_tools(self):
        jobs=[{'coverage_sha256':'x','build_identity':identity} for identity in ('a','b')]
        with self.assertRaisesRegex(ValueError,'compatible'):
            merge_coverage(ROOT,ROOT,{'jobs':jobs},{},threading.Event())

    def test_concurrent_latest_publication(self):
        from concurrent.futures import ThreadPoolExecutor
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'latest.json'
            with ThreadPoolExecutor(max_workers=4) as pool:
                list(pool.map(lambda i:save(path,{'campaign':i}),range(50)))
            self.assertIn(json.loads(path.read_text())['campaign'],range(50))
            self.assertEqual(list(Path(d).glob('*.tmp')),[])

    def test_html_escapes_names_and_junit_records_build_failure(self):
        with tempfile.TemporaryDirectory() as d:
            data={'core':'<script>','suite':'health','status':'FAIL','jobs':[{'id':'job-0','test':'<script>',
                  'seed':1,'run_mode':'base','status':'NOT_RUN'}], 'provenance':{'revision':'r','dirty':True},
                  'limitations':['<tag>'],'rerun_command':'echo test','builds':{}}
            render(Path(d),data)
            self.assertNotIn('<script></td>',(Path(d)/'health.html').read_text())
            self.assertIn('failures="1"',(Path(d)/'junit.xml').read_text())

if __name__=='__main__':unittest.main()
