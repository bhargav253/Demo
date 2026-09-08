# SPDX-License-Identifier: Apache-2.0
"""Build-once campaign scheduler. No HDL source lists or CPU-specific commands."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import importlib.metadata
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import threading
import sys
import uuid
import yaml

from .execution import run
from .cache import toolchain_identity
from .builds import build_one
from .model import sha, identity, validate, expand, load_policy, validate_parameters, tree_identity
from .report import save, render


def now():
    return datetime.now(timezone.utc).isoformat()


def provenance(root):
    def query(cmd):
        p=subprocess.run(cmd,cwd=root,capture_output=True,text=True,timeout=15)
        if p.returncode: raise RuntimeError(p.stderr or p.stdout)
        return p.stdout.strip()
    versions={tool:query([tool,flag]) for tool,flag in [('verilator','--version'),('g++','--version'),('make','--version')]}
    versions['python']=sys.version
    for package in ('axon-fusesoc','axon-edalize','PyYAML','fastjsonschema'):
        versions[package]=importlib.metadata.version(package)
    tool_sources={str(p.relative_to(root)):sha(p) for area in ('scripts/fusesoc','scripts/edalize')
                  for p in (root/area).rglob('*.py') if '__pycache__' not in p.parts}
    for relative in ('tools/bin/fusesoc','tools/env/bootstrap.py','requirements/tools.lock',
                     'scripts/fusesoc/pyproject.toml','scripts/edalize/pyproject.toml'):
        path=root/relative
        if path.is_file(): tool_sources[relative]=sha(path)
    status=query(['git','status','--porcelain'])
    resolved = {name:shutil.which(name) for name in ('verilator','verilator_coverage','g++','make')}
    resolved['python']=sys.executable
    return {'cache_toolchain': toolchain_identity(resolved),
            'cache_environment_sha256': identity({k:v for k,v in os.environ.items() if k not in ('PWD','OLDPWD','SHLVL','_')}),
            'revision':query(['git','rev-parse','HEAD']), 'dirty':bool(status), 'git_status':status,
            'diff_sha256':identity(query(['git','diff','HEAD','--binary'])),
            'tool_versions':versions,'repository_tools_sha256':identity(tool_sources),'source_tree_sha256':tree_identity(root),
            'resolved_tools':{name:shutil.which(name) for name in ('verilator','verilator_coverage','g++','make')},
            'build_environment':{name:os.environ[name] for name in ('CC','CXX','CFLAGS','CXXFLAGS','CPPFLAGS','LDFLAGS','MAKEFLAGS','VERILATOR_ROOT') if name in os.environ}}


def assess(result,text,build):
    if result['status']!='PASS': return result
    if re.search(build.get('fail_pattern',r'(?m)^(?:FAIL|%Error|%Fatal)'),text):
        return dict(result,status='FAIL',reason='Failure pattern found')
    if build.get('pass_pattern') and not re.search(build['pass_pattern'],text):
        return dict(result,status='FAIL',reason='Required pass pattern missing')
    return result


def simulator(work):
    paths=[p for p in work.glob('V*') if p.is_file() and os.access(p,os.X_OK) and '.' not in p.name]
    if len(paths)!=1: raise ValueError('Build did not produce exactly one simulator')
    return paths[0]


def execute_job(job,build,executable,directory,policy,cancel,root,core,config_hash):
    directory.mkdir(parents=True,exist_ok=True)
    selection={key:job[key] for key in ('id','test','run_mode','seed','build_mode','parameters','elf','input_hashes','timeout') if key in job}
    result=dict(selection, status='RUNNING', started_at=now(), core=core, config_sha256=config_hash,
                executable=str(executable), executable_sha256=sha(executable), build=build,
                policy=policy, artifact_directory=str(directory))
    params=dict(job['parameters'])
    if job.get('elf'):
        source=Path(job['elf'])
        expected=job['input_hashes'][str(source.relative_to(root))]
        snapshot=directory/'input.elf'
        shutil.copy2(source,snapshot)
        if sha(snapshot)!=expected: raise ValueError('ELF changed during snapshot')
        params['ELF']=str(snapshot)
        result['elf_snapshot']=str(snapshot)
        result['elf_sha256']=expected
    if build.get('wave_arg'): params[build['wave_arg']]=str(directory/'waves.fst')
    if build.get('coverage_arg'): params[build['coverage_arg']]=str(directory/'coverage.dat')
    command=[str(executable), *[f'+{key}={int(value) if isinstance(value,bool) else value}' for key,value in sorted(params.items())]]
    result['command']=command
    result['cwd']=str(directory)
    result['rerun_command']=shlex.join([str(root/'tools/bin/fusesoc'),'replay',str(directory/'run.json')])
    save(directory/'run.json',result)
    outcome=run(command,directory,directory/'sim.log',job.get('timeout') or policy['timeout'],
                policy['max_log_mib']*1024**2,policy['max_wave_mib']*1024**2,cancel)
    text=(directory/'sim.log').read_text(errors='replace')
    result.update(assess(outcome,text,build))
    if 'TIMEOUT' in text and result['status']=='FAIL': result['status']='TIMEOUT'
    cycles=re.search(r'\bcycles=(\d+)',text)
    if cycles: result['cycles']=int(cycles[1])
    if build.get('coverage_arg') and result['status']=='PASS':
        database=directory/'coverage.dat'
        if not database.is_file() or database.stat().st_size==0:
            result.update(status='FAIL',reason='Successful run produced no coverage database')
        else: result['coverage_sha256']=sha(database)
    if result['status']=='PASS':
        (directory/'waves.fst').unlink(missing_ok=True)
        (directory/'sim.log').write_text('\n'.join(text.splitlines()[-40:])+'\n')
    result['finished_at']=now()
    save(directory/'run.json',result)
    return result


def campaign(fs,args):
    core=fs.get_core(args.core)
    root=Path(fs.config._path).resolve().parent
    config=core.get_validation()
    if not config: raise ValueError(f'{args.core} has no validation declaration')
    validate(config,core._capi_data['targets'])
    policy=load_policy(root)
    if args.jobs is not None: policy['jobs']=args.jobs
    if args.timeout is not None: policy['timeout']=args.timeout
    if args.list:
        print(json.dumps(config,indent=2));return 0
    selected=expand(root,config,args.suite,args.test,args.seed,args.run_mode,args.action=='coverage')
    validate_parameters(core,config,selected)
    if args.dry_run:
        print(json.dumps({'core':str(core.name),'suite':args.suite,'jobs':selected},indent=2));return 0
    config_hash=identity(config)
    run_id=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S')+'-'+uuid.uuid4().hex[:8]
    safe=str(core.name).replace(':','_')
    directory=root/'artifacts'/safe/'validation'/run_id
    directory.mkdir(parents=True)
    command=[str(root/'tools/bin/fusesoc'),args.action,str(core.name)]
    if args.test: command+=['--test',args.test]
    else: command+=['--suite',args.suite]
    if args.seed is not None: command+=['--seed',str(args.seed)]
    if args.run_mode: command+=['--run-mode',args.run_mode]
    if getattr(args,'no_cache',False): command+=['--no-cache']
    command+=['--jobs',str(policy['jobs']),'--timeout',str(policy['timeout'])]
    data={'schema_version':1,'core':str(core.name),'suite':args.test or args.suite,
          'status':'RUNNING','started_at':now(),'provenance':provenance(root),
          'configuration':config,'config_sha256':config_hash,'policy':policy,
          'limitations':config['limitations'],'jobs':selected,'builds':{},
          'coverage':{'status':'NOT_MEASURED'},'rerun_command':shlex.join(command)}
    if getattr(args, 'impact', None):
        data['impact'] = args.impact
    render(directory,data)
    print(f'Campaign: {directory}\nSelected {len(selected)} jobs',flush=True)
    cancel=threading.Event()
    previous={s:signal.signal(s,lambda *_:cancel.set()) for s in (signal.SIGINT,signal.SIGTERM)}
    try:
        for name in dict.fromkeys(j['build_mode'] for j in selected):
            if cancel.is_set(): break
            build=config['build_modes'][name]
            work=root/'build'/'validation'/run_id/name
            retained=directory/'builds'/name
            retained.mkdir(parents=True)
            data['builds'][name]={'status':'RUNNING'}
            render(directory,data)
            print(f'Preparing {name}: {build["target"]}',flush=True)
            try:
                record=build_one(root,core,build,work,retained,directory,policy,data['provenance'],cancel,
                                 getattr(args,'no_cache',False))
            except Exception as exc:
                log=retained/'build.log'
                with log.open('a') as stream: stream.write(f'\nBuild integrity error: {exc}\n')
                record={'status':'FAIL','exit_status':1,'reason':str(exc),
                        'log':str(log.relative_to(directory)),
                        'cache':{'status':'BYPASS','reason':'Build integrity failure'}}
            print(f"Cache {name}: {record['cache']['status']} — {record['cache'].get('reason','')}",flush=True)
            data['builds'][name]=record
            save(retained/'build.json',record)
            print(f'Build {name}: {record["status"]}',flush=True)
            render(directory,data)
        state_lock=threading.Lock()
        def worker(job):
            build=config['build_modes'][job['build_mode']]
            built=data['builds'].get(job['build_mode'],{})
            if cancel.is_set():return dict(job,status='CANCELLED')
            if built.get('status')!='PASS':return dict(job,status='NOT_RUN',reason='Required build failed or was cancelled',log=built.get('log',''))
            if build['kind']=='target':return dict(job,status='PASS',log=built['log'],seconds=built['seconds'])
            with state_lock:
                job.update(status='RUNNING',started_at=now())
                render(directory,data)
            job_dir=directory/'runs'/job['id']
            try:
                if sha(built['executable']) != built['executable_sha256']:
                    raise ValueError('Campaign executable changed after build')
                result=execute_job(job,build,Path(built['executable']),job_dir,policy,cancel,root,str(core.name),config_hash)
                result['build_identity']=built['build_identity']
                result['log']=str((job_dir/'sim.log').relative_to(directory))
                save(job_dir/'run.json',result)
                return result
            except Exception as exc:
                result=dict(job,status='FAIL',reason=str(exc),log=str((job_dir/'sim.log').relative_to(directory)))
                job_dir.mkdir(parents=True,exist_ok=True)
                (job_dir/'sim.log').write_text(str(exc)+'\n')
                save(job_dir/'run.json',result)
                return result
        with ThreadPoolExecutor(max_workers=policy['jobs']) as pool:
            futures={pool.submit(worker,j):index for index,j in enumerate(selected)}
            for future in as_completed(futures):
                result=future.result()
                with state_lock:
                    data['jobs'][futures[future]]=result
                    render(directory,data)
                print(f"{result['status']}: {result['test']} mode={result['run_mode']} seed={result['seed']}",flush=True)
        data['status']='CANCELLED' if cancel.is_set() else ('PASS' if all(j['status']=='PASS' for j in data['jobs']) else 'FAIL')
        if args.action=='coverage':
            if data['status']=='PASS':
                merge_coverage(root,directory,data,policy,cancel)
            else:data['coverage']={'status':'NOT_MERGED','reason':'Campaign incomplete or failed; partial coverage is not published'}
    except Exception as exc:
        data.update(status='FAIL',error=str(exc))
        for record in data['builds'].values():
            if record['status']=='RUNNING': record.update(status='FAIL',reason=str(exc))
        for job in data['jobs']:
            if job['status'] in ('QUEUED','RUNNING'):job.update(status='NOT_RUN',reason='Campaign exception')
    finally:
        for sig,handler in previous.items():signal.signal(sig,handler)
        if cancel.is_set(): data['status']='CANCELLED'
        data['finished_at']=now()
        render(directory,data)
        save(directory.parent/'latest.json',{'manifest':str((directory/'run.json').relative_to(root))})
    print(f"Result: {data['status']}\nHealth: {directory/'health.html'}\nManifest: {directory/'run.json'}")
    args.campaign_status = data['status']
    args.campaign_manifest = str(directory/'run.json')
    return 0 if data['status']=='PASS' else 1


def merge_coverage(root,directory,data,policy,cancel):
    jobs=[j for j in data['jobs'] if 'coverage_sha256' in j]
    if not jobs or len({j['build_identity'] for j in jobs})!=1:
        raise ValueError('Coverage requires nonempty, compatible completed runs')
    databases=[directory/'runs'/j['id']/'coverage.dat' for j in jobs]
    for job,path in zip(jobs,databases):
        if sha(path)!=job['coverage_sha256']:raise ValueError('Coverage database changed before merge')
    out=directory/'coverage';out.mkdir()
    cmd=['verilator_coverage','--write',str(out/'merged.dat'),*map(str,databases)]
    result=run(cmd,root,out/'merge.log',policy['timeout'],policy['max_log_mib']*1024**2,
               policy['max_build_file_mib']*1024**2,cancel)
    if result['status']!='PASS':raise ValueError('Coverage merge failed; see coverage/merge.log')
    # Reuse the existing categorized database parser; do not duplicate metric semantics.
    import importlib.util
    spec=importlib.util.spec_from_file_location('axon_coverage_report',root/'scripts/coverage/report.py')
    reporter=importlib.util.module_from_spec(spec);spec.loader.exec_module(reporter)
    points=reporter.parse_database(out/'merged.dat')
    build=data['builds'][jobs[0]['build_mode']]
    excluded={f['name'] for f in build['identity_inputs']['edam']['files']
              if 'coverage_exclude' in f.get('tags',[])}
    excluded_count=0
    for category in points:
        if category != 'v_user':
            kept=[p for p in points[category] if p['file'] not in excluded]
            excluded_count+=len(points[category])-len(kept)
            points[category]=kept
    summary=reporter.summarize(points)
    summary['excluded_support_points']=excluded_count
    summary['excluded_files']=sorted(excluded)
    if not summary['total']:raise ValueError('Merged coverage contains no measured points')
    save(out/'summary.json',summary)
    (out/'summary.txt').write_text(reporter.render(summary))
    data['coverage']=dict(summary,status='MEASURED',build_identity=jobs[0]['build_identity'],
                          inputs=[str(p.relative_to(directory)) for p in databases],
                          merged_sha256=sha(out/'merged.dat'),command=cmd)
