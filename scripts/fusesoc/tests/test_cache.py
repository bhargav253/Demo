# SPDX-License-Identifier: Apache-2.0
"""Cache identity, publication, corruption, cancellation and prune isolation."""
import copy
import json
import multiprocessing
import os
from pathlib import Path
import tempfile
import threading
import unittest

from fusesoc.validation.cache import Cache, canonical_inputs, eligibility
from fusesoc.validation.model import identity


def contender(root, key, inputs, counter):
    cache = Cache(root)
    with cache.lock(key, threading.Event()):
        record, _ = cache.check(key)
        if not record:
            with open(counter, 'a') as stream:
                stream.write('compiled\n')
            cache.publish(key, inputs, Path(root)/'exe', Path(root)/'log', {})


class CacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cache = Cache(self.root)
        self.work = self.root/'build/work'
        self.work.mkdir(parents=True)
        (self.work/'design.sv').write_text('module dut; endmodule\n')
        (self.root/'exe').write_text('simulator')
        (self.root/'log').write_text('build succeeded')
        self.edam = {'files': [{'name': 'design.sv'}], 'parameters': {
            'SEED': {'paramtype': 'plusarg', 'default': 1},
            'Width': {'paramtype': 'vlogparam', 'default': 8}},
            'flow_options': {'tool': 'verilator'}}
        self.provenance = {'tool_versions': {'verilator': '5'}, 'repository_tools_sha256': 'source',
                           'cache_toolchain': {'compiler': 'abc'}, 'cache_environment_sha256': 'env'}

    def inputs(self):
        return canonical_inputs(self.edam, self.work, self.root, self.provenance)

    def publish(self):
        inputs = self.inputs(); key = identity(inputs)
        with self.cache.lock(key, threading.Event()):
            self.cache.publish(key, inputs, self.root/'exe', self.root/'log', {})
        return key

    def test_runtime_inputs_do_not_change_key(self):
        before = self.inputs()
        self.edam['parameters']['SEED']['default'] = 42
        self.edam['parameters']['ELF'] = {'paramtype': 'plusarg', 'default': '/different/input.elf'}
        self.assertEqual(before, self.inputs())

    def test_compile_source_tool_and_environment_changes_invalidate(self):
        before = self.inputs()
        self.edam['parameters']['Width']['default'] = 16
        self.assertNotEqual(before, self.inputs())
        self.edam['parameters']['Width']['default'] = 8
        for field in ('tool_versions', 'repository_tools_sha256', 'cache_toolchain', 'cache_environment_sha256'):
            old = copy.deepcopy(self.provenance[field])
            self.provenance[field] = {'changed': True}
            self.assertNotEqual(before, self.inputs(), field)
            self.provenance[field] = old
        (self.work/'design.sv').write_text('changed')
        self.assertNotEqual(before, self.inputs())

    def test_unlisted_exported_headers_and_generator_outputs_invalidate(self):
        directory = self.work/'src'; directory.mkdir()
        before = self.inputs()
        (directory/'generated.svh').write_text('new generated output')
        self.assertNotEqual(before, self.inputs())
        previous = self.inputs()
        (directory/'generated.svh').write_text('changed template output')
        self.assertNotEqual(previous, self.inputs())

    def test_work_directory_is_not_an_identity_input(self):
        self.edam['flow_options']['path'] = str(self.work/'somewhere')
        before = self.inputs()
        new_work = self.root/'build/other'; new_work.mkdir()
        (new_work/'design.sv').write_text((self.work/'design.sv').read_text())
        self.edam['flow_options']['path'] = str(new_work/'somewhere')
        self.assertEqual(before, canonical_inputs(self.edam, new_work, self.root, self.provenance))

    def test_complete_entry_restores_private_copy(self):
        key = self.publish()
        dest = self.root/'retained'; dest.mkdir()
        with self.cache.lock(key, threading.Event()):
            record, _ = self.cache.restore(key, dest)
        self.assertIsNotNone(record)
        self.assertNotEqual((dest/'simulator').stat().st_ino, (self.cache.entry(key)/'simulator').stat().st_ino)
        self.assertEqual((dest/'simulator').stat().st_mode & 0o222, 0)
        self.cache.prune(0, threading.Event())
        self.assertEqual((dest/'simulator').read_text(), 'simulator')

    def test_corruption_and_incomplete_entries_are_misses(self):
        key = self.publish()
        binary = self.cache.entry(key)/'simulator'
        binary.chmod(0o755); binary.write_text('corrupted')
        self.assertIsNone(self.cache.check(key)[0])
        self.cache.remove(key)
        self.cache.entry(key).mkdir()
        (self.cache.entry(key)/'simulator').write_text('partial')
        self.assertIsNone(self.cache.check(key)[0])

    def test_publish_rejects_wrong_identity_and_never_leaves_partial_entry(self):
        inputs = self.inputs()
        with self.assertRaises(ValueError):
            self.cache.publish('0'*64, inputs, self.root/'exe', self.root/'log', {})
        key = identity(inputs)
        with self.assertRaises(FileNotFoundError):
            self.cache.publish(key, inputs, self.root/'missing', self.root/'log', {})
        self.assertFalse(self.cache.entry(key).exists())
        self.assertEqual(list((self.cache.root/'entries').iterdir()), [])

    def test_two_processes_publish_one_compilation(self):
        inputs = self.inputs(); key = identity(inputs)
        counter = self.root/'counter'
        processes = [multiprocessing.Process(target=contender, args=(self.root, key, inputs, counter)) for _ in range(2)]
        for process in processes: process.start()
        for process in processes:
            process.join(10)
            self.assertEqual(process.exitcode, 0)
        self.assertEqual(counter.read_text().splitlines(), ['compiled'])
        self.assertIsNotNone(self.cache.check(key)[0])

    def test_lock_cancel_timeout_and_prune_skip_busy(self):
        key = self.publish()
        with self.cache.lock(key, threading.Event()):
            with self.assertRaises(TimeoutError):
                with self.cache.lock(key, threading.Event(), timeout=.01): pass
            cancelled = threading.Event(); cancelled.set()
            with self.assertRaises(InterruptedError):
                with self.cache.lock(key, cancelled): pass
            self.assertEqual(self.cache.prune(0, threading.Event())['busy'], [key])
        result = self.cache.prune(0, threading.Event(), dry_run=True)
        self.assertEqual(result['would_remove'], [key])
        self.assertTrue(self.cache.entry(key).exists())
        self.assertEqual(self.cache.prune(0, threading.Event())['removed'], [key])

    def test_unsupported_external_options_bypass(self):
        self.assertIsNone(eligibility(self.edam))
        self.edam['flow_options']['verilator_options'] = ['-I/external/include']
        self.assertIsNotNone(eligibility(self.edam))
        self.edam['flow_options'] = {'tool': 'other'}
        self.assertIsNotNone(eligibility(self.edam))

    def test_orphan_cleanup_preserves_active_publication(self):
        inputs = self.inputs(); key = identity(inputs)
        orphan = self.cache.root/'entries'/('.tmp-'+key+'-abc')
        orphan.mkdir(); (orphan/'simulator').write_text('partial')
        with self.cache.lock(key, threading.Event()):
            result = self.cache.prune(0, threading.Event())
            self.assertIn(orphan.name, result['busy'])
            self.assertTrue(orphan.exists())
        self.assertEqual(self.cache.prune(0, threading.Event())['orphan_directories'], [orphan.name])
        self.assertFalse(orphan.exists())

    def test_options_and_declared_include_directory_contents_invalidate(self):
        before = self.inputs()
        self.edam['flow_options']['verilator_options'] = ['--assert']
        self.assertNotEqual(before, self.inputs())
        include = self.work/'include'; include.mkdir()
        self.edam['files'][0]['include_path'] = 'include'
        before = self.inputs()
        (include/'new.svh').write_text('new shadowing header')
        self.assertNotEqual(before, self.inputs())
