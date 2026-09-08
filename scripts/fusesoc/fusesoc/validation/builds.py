# SPDX-License-Identifier: Apache-2.0
"""Prepare every build through FuseSoC, then reuse eligible compiled simulators."""
from contextlib import nullcontext
import os
from pathlib import Path
import shutil
import time
import yaml

from .cache import Cache, canonical_inputs, eligibility
from .execution import run
from .model import identity, sha


def build_one(root, core, build, work, retained, directory, policy, provenance, cancel, no_cache=False):
    from .engine import assess, simulator, provenance as current_provenance
    start = time.monotonic()
    base = [str(root/'tools/bin/fusesoc'), 'run', '--target', build['target'],
            '--work-root', str(work), str(core.name)]
    parameters = [f'--{key}={value}' for key, value in sorted(build.get('parameters', {}).items())]
    def execute(stage, log):
        command = base[:2] + ([stage] if stage else []) + base[2:] + parameters
        outcome = run(command, root, retained/log, build.get('timeout', policy['timeout']),
                      policy['max_log_mib']*1024**2, policy['max_build_file_mib']*1024**2, cancel)
        return dict(outcome, command=command, log=str((retained/log).relative_to(directory)))
    # Target checks are always fresh; successful lint/formal is not a cache hit.
    if build['kind'] != 'simulation':
        record = execute(None, 'build.log')
        if record['status'] == 'PASS':
            record = assess(record, (retained/'build.log').read_text(errors='replace'), build)
        record['cache'] = {'status': 'BYPASS', 'reason': 'Target checks execute fresh'}
        return record

    setup = execute('--setup', 'setup.log')
    if setup['status'] != 'PASS':
        return dict(setup, cache={'status': 'BYPASS', 'reason': 'Build setup failed'})
    edam_path = next(work.glob('*.eda.yml'))
    edam = yaml.safe_load(edam_path.read_text())
    shutil.copyfile(edam_path, retained/'build.eda.yml')
    inputs = canonical_inputs(edam, work, root, provenance)
    key = identity(inputs)
    reason = 'Explicit --no-cache' if no_cache else eligibility(edam)
    if not provenance['cache_toolchain'].get('system_packages_sha256'):
        reason = reason or 'Unqualified system toolchain installation'
    if any(os.environ.get(key) for key in ('CC', 'CXX', 'EDALIZE_LAUNCHER', 'MAKE', 'AR', 'LD_PRELOAD')):
        reason = reason or 'Custom compiler/launcher requires an explicit cache adapter'
    if any(any(token in os.environ.get(key, '') for token in ('-I', '-L', '-l', '@', '--sysroot'))
           for key in ('CFLAGS', 'CXXFLAGS', 'CPPFLAGS', 'LDFLAGS')):
        reason = reason or 'External build environment inputs require uncached execution'
    cache = Cache(root)
    cache_info = {'status': 'BYPASS' if reason else 'MISS', 'key': key, 'reason': reason}
    try:
        with (cache.lock(key, cancel, policy['timeout']) if not reason else nullcontext()):
            hit, explanation = (None, reason) if reason else cache.restore(key, retained)
            if hit:
                record = {'status': 'PASS', 'exit_status': 0, 'seconds': time.monotonic()-start,
                          'command': setup['command'], 'log': str((retained/'build.log').relative_to(directory))}
                cache_info.update(status='HIT', reason=explanation, origin=hit['origin'])
            else:
                cache_info['reason'] = explanation
                record = execute('--build', 'build.log')
                if record['status'] == 'PASS':
                    # The normal FuseSoC build resolves again; never publish if
                    # generator/source inputs changed between setup and compile.
                    actual = yaml.safe_load(edam_path.read_text())
                    if canonical_inputs(actual, work, root, provenance) != inputs:
                        raise ValueError('Build inputs changed after cache selection')
                    observed = current_provenance(root)
                    if any(observed[field] != provenance[field] for field in
                           ('tool_versions', 'repository_tools_sha256', 'cache_toolchain', 'cache_environment_sha256')):
                        raise ValueError('Build toolchain changed during compilation')
                    shutil.copyfile(simulator(work), retained/'simulator')
                    (retained/'simulator').chmod(0o555)
                    if not reason and not cancel.is_set():
                        cache.publish(key, inputs, retained/'simulator', retained/'build.log',
                                      {'core': str(core.name), 'build_manifest': str(retained/'build.json'),
                                       'command': record['command']})
            record.update(setup=setup, cache=cache_info, identity_inputs=inputs, build_identity=key)
            if record['status'] == 'PASS':
                executable = retained/'simulator'
                record.update(executable=str(executable), executable_sha256=sha(executable))
            return record
    except (InterruptedError, TimeoutError) as exc:
        return dict(setup, status='CANCELLED' if cancel.is_set() else 'TIMEOUT',
                    exit_status=130 if cancel.is_set() else 124, reason=str(exc), cache=cache_info)
