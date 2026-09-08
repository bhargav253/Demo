# SPDX-License-Identifier: Apache-2.0
"""Validate declarations and deterministically expand tests into concrete jobs."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import fastjsonschema
from .schema import SCHEMA, POLICY


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for chunk in iter(lambda:f.read(1024*1024), b''):
            h.update(chunk)
    return h.hexdigest()


def identity(data):
    return hashlib.sha256(json.dumps(data, sort_keys=True, separators=(',',':')).encode()).hexdigest()


def inside(root, path):
    result = (root / path).resolve()
    if not result.is_relative_to(root.resolve()):
        raise ValueError(f'Path escapes repository: {path}')
    return result


def load_policy(root):
    result = json.loads((root/'verification/validation.json').read_text())
    fastjsonschema.validate(POLICY, result)
    return result


def validate(config, targets):
    fastjsonschema.validate(SCHEMA, config)
    for name, build in config['build_modes'].items():
        if build['target'] not in targets:
            raise ValueError(f'Build mode {name}: unknown target {build["target"]}')
        for field in ('pass_pattern','fail_pattern'):
            if field in build:
                re.compile(build[field])
        if build['kind'] == 'simulation' and 'pass_pattern' not in build:
            raise ValueError(f'{name}: simulation needs an explicit pass_pattern')
    for name, test in config['tests'].items():
        if test['build_mode'] not in config['build_modes']:
            raise ValueError(f'{name}: unknown build mode')
        if 'manifest' in test and config['build_modes'][test['build_mode']]['kind'] != 'simulation':
            raise ValueError('Firmware manifests require a simulation build')
    if config.get('coverage_build_mode') not in (None, *config['build_modes']):
        raise ValueError('Unknown coverage build mode')
    for entries in config['regressions'].values():
        for entry in entries:
            if not set(entry['tests']) <= config['tests'].keys():
                raise ValueError('Regression names an unknown test')
            if not set(entry.get('run_modes',['base'])) <= config['run_modes'].keys():
                raise ValueError('Regression names an unknown run mode')


def inputs(root, test):
    if 'manifest' not in test:
        return [(None, None, {})]
    path = inside(root, test['manifest'])
    manifest = json.loads(path.read_text())
    if not manifest.get('tests'):
        raise ValueError(f'Empty firmware manifest: {path}')
    hashes = {str(path.relative_to(root)):sha(path)}
    if 'config_sha256' in manifest:
        config = inside(root, path.parent/manifest['config_directory'])
        for name, expected in manifest['config_sha256'].items():
            file = inside(root, config/name)
            if sha(file) != expected:
                raise ValueError(f'Platform configuration checksum mismatch: {file}')
            hashes[str(file.relative_to(root))] = expected
    result = []
    for item in manifest['tests']:
        file = inside(root, path.parent/item['file'])
        if sha(file) != item['sha256']:
            raise ValueError(f'ELF checksum mismatch: {file}')
        result.append((file.stem, str(file), dict(hashes, **{str(file.relative_to(root)):item['sha256']})))
    return result


def expand(root, config, suite, test=None, seed=None, run_mode=None, coverage=False):
    if test:
        parent = test.split('/')[0]
        if parent not in config['tests']:
            raise ValueError(f'Unknown test {test}')
        entries = [{'tests':[parent], 'run_modes':[run_mode or 'base'], 'seeds':[seed if seed is not None else 1]}]
    else:
        if suite not in config['regressions']:
            raise ValueError(f'Unknown suite {suite}; choose {list(config["regressions"])}')
        entries = config['regressions'][suite]
    jobs = []
    seen = set()
    for entry in entries:
        for name in entry['tests']:
            definition = config['tests'][name]
            build_name = definition['build_mode']
            build = config['build_modes'][build_name]
            if coverage and build['kind'] == 'simulation':
                build_name = config.get('coverage_build_mode')
                if not build_name:
                    raise ValueError('No coverage build declared')
                build = config['build_modes'][build_name]
                if build['kind'] != 'simulation' or not build.get('coverage_arg'):
                    raise ValueError('Coverage build requires simulation kind and coverage_arg')
            for suffix, elf, hashes in inputs(root, definition):
                full_name = name + ('/'+suffix if suffix else '')
                if test and '/' in test and full_name != test:
                    continue
                for mode in ([run_mode] if run_mode else entry.get('run_modes',['base'])):
                    if mode not in config['run_modes']:
                        raise ValueError(f'Unknown run mode {mode}')
                    for value in ([seed] if seed is not None else entry.get('seeds',[1])):
                        key = (full_name, mode, value, build_name)
                        if key in seen:
                            continue
                        seen.add(key)
                        parameters = dict(definition.get('parameters',{}), **config['run_modes'][mode].get('parameters',{}))
                        if build['kind'] == 'simulation':
                            parameters['SEED'] = value
                        jobs.append(dict(id=f'job-{len(jobs):04d}', test=full_name, run_mode=mode,
                                         seed=value, build_mode=build_name, parameters=parameters,
                                         elf=elf, input_hashes=hashes, timeout=definition.get('timeout'),
                                         status='QUEUED'))
    if not jobs:
        raise ValueError('Selection contains no jobs')
    return jobs


def validate_parameters(core, config, jobs):
    """Prevent runtime overrides from silently changing elaboration or being ignored."""
    metadata = core._capi_data.get('parameters', {})
    targets = core._capi_data['targets']
    for build in config['build_modes'].values():
        allowed = {p.split('=', 1)[0] for p in targets[build['target']].get('parameters', [])}
        for key in build.get('parameters', {}):
            if key not in allowed or metadata[key]['paramtype'] == 'plusarg':
                raise ValueError(f'{key}: build parameters must be declared compile-time parameters')
    for job in jobs:
        build = config['build_modes'][job['build_mode']]
        if build['kind'] != 'simulation':
            continue
        allowed = {p.split('=', 1)[0] for p in targets[build['target']].get('parameters', [])}
        names = set(job['parameters'])
        names.update(build[k] for k in ('wave_arg','coverage_arg') if build.get(k))
        if job.get('elf'): names.add('ELF')
        for key in names:
            if key not in allowed or metadata[key]['paramtype'] != 'plusarg':
                raise ValueError(f'{key}: runtime inputs must be declared plusargs on {build["target"]}')


def tree_identity(root):
    paths=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=root).decode().split('\0')
    return identity({p:sha(root/p) if (root/p).is_file() else None for p in sorted(set(paths)) if p})
