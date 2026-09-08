# SPDX-License-Identifier: Apache-2.0
"""Exercise actual FuseSoC resolution and Git change detection for smoke selection."""
import json
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace
import yaml

from fusesoc.config import Config
from fusesoc.fusesoc import Fusesoc
from fusesoc.validation.impact import changed_paths, select, invoke


class ImpactTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root/'fusesoc.conf').write_text('[main]\ncores_root = '+str(self.root/'ip')+'\ncache_root = '+str(self.root/'cache')+'\n')
        self.core('cpu')
        self.core('pe', ['cpu'])
        self.core('mesh', ['pe', 'cpu'])
        self.core('unrelated')

    def core(self, name, deps=(), validation=True):
        directory = self.root/'ip'/name
        directory.mkdir(parents=True, exist_ok=True)
        (directory/(name+'.sv')).write_text('module '+name+'; endmodule\n')
        data = {'name': 'test:ip:'+name+':1.0',
                'filesets': {'rtl': {'files': [name+'.sv'], 'file_type': 'systemVerilogSource',
                                     'depend': ['test:ip:'+d+':1.0' for d in deps]}},
                'targets': {'default': {'filesets': ['rtl']}, 'lint': {'filesets': ['rtl']}}}
        if validation:
            data['validation'] = {'version': 1, 'build_modes': {'lint': {'target': 'lint', 'kind': 'target'}},
                'run_modes': {'base': {}}, 'tests': {'check': {'build_mode': 'lint'}},
                'regressions': {'smoke': [{'tests': ['check']}]}, 'limitations': ['Fixture only']}
        (directory/(name+'.core')).write_text('CAPI=2:\n'+yaml.safe_dump(data))

    def fs(self):
        return Fusesoc(Config(str(self.root/'fusesoc.conf')))

    def names(self, plan):
        return [item['core'].split(':')[2] for item in plan['selected']]

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root).decode().strip()

    def initialize_git(self):
        (self.root/'.gitignore').write_text('artifacts/\nbuild/\ncache/\n')
        self.git('init', '-q')
        self.git('add', '.')
        self.git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'initial')

    def test_transitive_consumers_deduplicate_and_exclude_unrelated(self):
        fs = self.fs()
        plan = select(fs, self.root, ['ip/cpu/cpu.sv'])
        self.assertEqual(self.names(plan), ['cpu', 'mesh', 'pe'])
        self.assertEqual(plan['job_count'], 3)
        self.assertEqual(plan, select(fs, self.root, ['ip/cpu/cpu.sv']))
        self.assertEqual(plan['graph_errors'], [])
        pe = next(x for x in plan['selected'] if ':pe:' in x['core'])
        self.assertEqual(pe['reasons'][0]['dependency_path'], ['test:ip:cpu:1.0', 'test:ip:pe:1.0'])

    def test_transitive_only_chain(self):
        self.core('mesh', ['pe'])
        plan = select(self.fs(), self.root, ['ip/cpu/cpu.sv', 'ip/pe/pe.sv'])
        mesh = next(x for x in plan['selected'] if ':mesh:' in x['core'])
        self.assertEqual(mesh['reasons'][0]['dependency_path'],
                         ['test:ip:cpu:1.0', 'test:ip:pe:1.0', 'test:ip:mesh:1.0'])
        self.assertEqual(plan['job_count'], 3)

    def test_unrelated_change_does_not_select_cpu(self):
        self.assertEqual(self.names(select(self.fs(), self.root, ['ip/unrelated/unrelated.sv'])), ['unrelated'])

    def test_unknown_and_full_select_all(self):
        for paths, full in [(['tools/shared.py'], False), ([], True)]:
            plan = select(self.fs(), self.root, paths, full=full)
            self.assertEqual(len(plan['selected']), 4)
            self.assertTrue(plan['fallback_reasons'])

    def test_missing_smoke_is_visible(self):
        self.core('pe', ['cpu'], validation=False)
        plan = select(self.fs(), self.root, ['ip/cpu/cpu.sv'])
        self.assertEqual([x['core'] for x in plan['missing_suites']], ['test:ip:pe:1.0'])

    def test_unresolved_dependency_broadens_selection(self):
        self.core('pe', ['missing'])
        plan = select(self.fs(), self.root, ['ip/cpu/cpu.sv'])
        self.assertTrue(plan['graph_errors'])
        self.assertEqual(len(plan['selected']), 4)

    def test_deleted_and_unlisted_local_sources(self):
        for path in ['ip/cpu/deleted.sv', 'ip/cpu/new.svh', 'ip/cpu/cpu.core']:
            self.assertEqual(self.names(select(self.fs(), self.root, [path])), ['cpu', 'mesh', 'pe'])

    def test_target_specific_dependency(self):
        path = self.root/'ip/pe/pe.core'
        data = yaml.safe_load(path.read_text().split('\n', 1)[1])
        data['filesets']['rtl']['depend'] = []
        data['filesets']['dv'] = {'depend': ['test:ip:cpu:1.0']}
        data['targets']['lint']['filesets'].append('dv')
        path.write_text('CAPI=2:\n'+yaml.safe_dump(data))
        self.assertEqual(self.names(select(self.fs(), self.root, ['ip/cpu/cpu.sv'])), ['cpu', 'mesh', 'pe'])

    def test_git_committed_staged_unstaged_deleted_renamed_untracked(self):
        self.initialize_git()
        base = self.git('rev-parse', 'HEAD')
        (self.root/'committed').write_text('x')
        self.git('add', 'committed')
        self.git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'next')
        self.git('mv', 'ip/cpu/cpu.sv', 'ip/cpu/renamed.sv')
        (self.root/'ip/pe/pe.sv').unlink()
        (self.root/'ip/mesh/mesh.sv').write_text('changed')
        (self.root/'new').write_text('untracked')
        actual_base, paths = changed_paths(self.root, base)
        self.assertEqual(actual_base, base)
        for path in ['committed', 'ip/cpu/cpu.sv', 'ip/cpu/renamed.sv', 'ip/pe/pe.sv', 'ip/mesh/mesh.sv', 'new']:
            self.assertIn(path, paths)

    def test_dispatch_runs_each_consumer_suite_once(self):
        self.initialize_git()
        (self.root/'ip/cpu/cpu.sv').write_text('changed')
        args = SimpleNamespace(base='HEAD', suite='smoke', full=False, dry_run=False, jobs=2, timeout=30)
        with patch('fusesoc.validation.engine.campaign', return_value=0) as run:
            self.assertEqual(invoke(self.fs(), args), 0)
        self.assertEqual([call.args[1].core for call in run.call_args_list],
            ['test:ip:cpu:1.0', 'test:ip:mesh:1.0', 'test:ip:pe:1.0'])
        self.assertTrue(all(call.args[1].suite == 'smoke' for call in run.call_args_list))
        plan = json.loads(next((self.root/'artifacts/impact').glob('*/selection.json')).read_text())
        self.assertEqual(plan['status'], 'PASS')

    def test_missing_suite_blocks_execution(self):
        self.core('pe', ['cpu'], validation=False)
        self.initialize_git()
        (self.root/'ip/cpu/cpu.sv').write_text('changed')
        args = SimpleNamespace(base='HEAD', suite='smoke', full=False, dry_run=False, jobs=None, timeout=None)
        with patch('fusesoc.validation.engine.campaign') as run:
            self.assertEqual(invoke(self.fs(), args), 2)
            run.assert_not_called()

    @unittest.skipUnless(shutil.which('verilator'), 'Verilator required for actual consumer builds')
    def test_real_cli_builds_and_runs_transitive_consumer_smokes(self):
        # All three selected cores have real Verilator lint smoke targets.
        self.core('mesh', ['pe'])
        for path in (self.root/'ip').glob('*/*.core'):
            data = yaml.safe_load(path.read_text().split('\n', 1)[1])
            name = data['name'].split(':')[2]
            data['targets']['lint'].update(flow='lint', flow_options={'tool': 'verilator'}, toplevel=name)
            path.write_text('CAPI=2:\n'+yaml.safe_dump(data))
        launcher = self.root/'tools/bin/fusesoc'
        launcher.parent.mkdir(parents=True)
        launcher.write_text('#!'+sys.executable+'\nimport sys\nfrom fusesoc.main import main\nsys.argv[1:1] = '+repr(['--config', str(self.root/'fusesoc.conf')])+'\nmain()\n')
        launcher.chmod(0o755)
        (self.root/'verification').mkdir()
        source = Path(__file__).resolve().parents[3]/'verification/validation.json'
        shutil.copy(source, self.root/'verification/validation.json')
        self.initialize_git()
        with (self.root/'ip/cpu/cpu.sv').open('a') as stream:
            stream.write('// changed CPU source\n')
        result = subprocess.run([str(launcher), 'presubmit', '--base', 'HEAD'],
                                cwd=self.root, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        plan = json.loads(next((self.root/'artifacts/impact').glob('*/selection.json')).read_text())
        self.assertEqual(self.names(plan), ['cpu', 'mesh', 'pe'])
        self.assertEqual(plan['status'], 'PASS')
        for item in plan['selected']:
            record = json.loads(Path(item['campaign_manifest']).read_text())
            self.assertEqual(record['status'], 'PASS')
            self.assertEqual(record['impact']['reasons'], item['reasons'])

    def test_conditional_dependencies_resolve_without_unrelated_cores(self):
        path = self.root/'ip/pe/pe.core'
        data = yaml.safe_load(path.read_text().split('\n', 1)[1])
        data['filesets']['rtl']['depend'] = ['optional ? (test:ip:cpu:1.0)']
        path.write_text('CAPI=2:\n'+yaml.safe_dump(data))
        plan = select(self.fs(), self.root, ['ip/cpu/cpu.sv'])
        self.assertFalse(plan['graph_errors'])
        self.assertEqual(self.names(plan), ['cpu', 'mesh', 'pe'])

    def test_failed_campaign_is_not_aggregate_pass(self):
        self.initialize_git()
        (self.root/'ip/cpu/cpu.sv').write_text('changed')
        args = SimpleNamespace(base='HEAD', suite='smoke', full=False, dry_run=False, jobs=None, timeout=None)
        with patch('fusesoc.validation.engine.campaign', side_effect=[0, 1, 0]) as run:
            self.assertEqual(invoke(self.fs(), args), 1)
            self.assertEqual(run.call_count, 3)
        plan = json.loads(next((self.root/'artifacts/impact').glob('*/selection.json')).read_text())
        self.assertEqual(plan['status'], 'FAIL')

    def test_source_change_during_execution_rejects_selection(self):
        self.initialize_git()
        (self.root/'ip/cpu/cpu.sv').write_text('changed')
        args = SimpleNamespace(base='HEAD', suite='smoke', full=False, dry_run=False, jobs=None, timeout=None)
        def mutate(fs, options):
            (self.root/'ip/unrelated/unrelated.sv').write_text('new concurrent change')
            return 0
        with patch('fusesoc.validation.engine.campaign', side_effect=mutate) as run:
            self.assertEqual(invoke(self.fs(), args), 2)
            self.assertEqual(run.call_count, 1)
        plan = json.loads(next((self.root/'artifacts/impact').glob('*/selection.json')).read_text())
        self.assertEqual(plan['status'], 'FAIL')

    def write_policy(self, rules):
        (self.root/'verification').mkdir(exist_ok=True)
        (self.root/'verification/impact.json').write_text(json.dumps({'version': 1, 'rules': rules}))

    def test_documentation_is_explicit_and_owned_inputs_take_precedence(self):
        self.write_policy([{'paths': ['docs/**', '**/README.md'], 'kind': 'documentation', 'reason': 'Docs'}])
        plan = select(self.fs(), self.root, ['docs/guide.md'])
        self.assertEqual(plan['selected'], [])
        self.assertEqual(plan['classifications'][0]['kind'], 'documentation')
        (self.root/'platforms/cpu').mkdir(parents=True)
        (self.root/'platforms/cpu/platform.json').write_text(json.dumps(
            {'hardware_core': 'test:ip:cpu:1.0', 'memory_contract': 'docs/contract.md'}))
        self.assertEqual(self.names(select(self.fs(), self.root, ['docs/contract.md'])), ['cpu', 'mesh', 'pe'])

    def test_firmware_config_and_elf_ownership_from_manifest(self):
        from fusesoc.validation.model import sha
        folder = self.root/'prebuilt'; folder.mkdir()
        (folder/'program.elf').write_text('ELF fixture')
        (folder/'link.ld').write_text('linker fixture')
        manifest = {'tests': [{'file': 'program.elf', 'sha256': sha(folder/'program.elf')}],
                    'config_directory': '.', 'config_sha256': {'link.ld': sha(folder/'link.ld')}}
        (folder/'manifest.json').write_text(json.dumps(manifest))
        path = self.root/'ip/cpu/cpu.core'
        data = yaml.safe_load(path.read_text().split('\n', 1)[1])
        data['targets']['sim'] = {'filesets': ['rtl'], 'parameters': ['SEED', 'ELF']}
        data['parameters'] = {name: {'datatype': 'str', 'paramtype': 'plusarg'} for name in ['SEED', 'ELF']}
        cfg = data['validation']
        cfg['build_modes']['sim'] = {'target': 'sim', 'kind': 'simulation', 'pass_pattern': 'PASS'}
        cfg['tests']['fw'] = {'build_mode': 'sim', 'manifest': 'prebuilt/manifest.json'}
        path.write_text('CAPI=2:\n'+yaml.safe_dump(data))
        for changed in ['prebuilt/program.elf', 'prebuilt/link.ld', 'prebuilt/manifest.json', 'prebuilt/new_header.h']:
            plan = select(self.fs(), self.root, [changed])
            self.assertEqual(self.names(plan), ['cpu', 'mesh', 'pe'])
            self.assertEqual(plan['fallback_reasons'], [])
        (folder/'link.ld').write_text('changed without rebuilt firmware')
        with self.assertRaisesRegex(ValueError, 'checksum'):
            select(self.fs(), self.root, ['prebuilt/link.ld'])

    def test_explicit_generator_input_rule_selects_owner_and_consumers(self):
        self.write_policy([{'paths': ['schemas/cpu/**'], 'kind': 'owners', 'cores': ['test:ip:cpu:1.0'],
                            'reason': 'CPU generator schemas'}])
        self.assertEqual(self.names(select(self.fs(), self.root, ['schemas/cpu/new.json'])), ['cpu', 'mesh', 'pe'])

    def test_global_fallback_reports_unqualified_cores(self):
        self.core('unrelated', validation=False)
        plan = select(self.fs(), self.root, ['tools/shared.py'])
        self.assertEqual(plan['missing_suites'][0]['core'], 'test:ip:unrelated:1.0')
        self.assertEqual(plan['missing_suites'][0]['qualification'], 'missing_suite')

    def test_invalid_core_cannot_disappear_from_gate(self):
        folder = self.root/'ip/bad'; folder.mkdir()
        (folder/'bad.core').write_text('CAPI=2:\nname: bad\nunknown_field: true\n')
        plan = select(self.fs(), self.root, ['ip/cpu/cpu.sv'])
        self.assertTrue(any('not registered' in error for error in plan['graph_errors']))
        self.assertFalse(plan['selection_complete'])

    def test_policy_unknown_owner_is_rejected(self):
        self.write_policy([{'paths': ['schemas/**'], 'kind': 'owners', 'cores': ['test:ip:absent:1.0'], 'reason': 'Bad owner'}])
        with self.assertRaisesRegex(ValueError, 'unknown core'):
            select(self.fs(), self.root, ['schemas/cpu.json'])

    def test_docs_only_cli_records_no_hardware_checks(self):
        self.write_policy([{'paths': ['docs/**'], 'kind': 'documentation', 'reason': 'Docs'}])
        self.initialize_git()
        (self.root/'docs').mkdir(); (self.root/'docs/guide.md').write_text('guide')
        args = SimpleNamespace(base='HEAD', suite='smoke', full=False, dry_run=False, jobs=None, timeout=None)
        with patch('fusesoc.validation.engine.campaign') as run:
            self.assertEqual(invoke(self.fs(), args), 0)
            run.assert_not_called()
        record = json.loads(next((self.root/'artifacts/impact').glob('*/selection.json')).read_text())
        self.assertEqual(record['status'], 'NO_HARDWARE_CHANGES')
