# SPDX-License-Identifier: Apache-2.0
"""Non-HDL ownership from existing manifests and explicit repository policy."""
import fnmatch
import itertools
import json
from pathlib import Path
import fastjsonschema

from fusesoc.capi2.exprs import Exprs

from .model import inside
from .schema import obj, string, strings

RULE = obj({'paths': strings, 'kind': {'enum': ['documentation', 'global', 'owners']},
            'cores': strings, 'reason': string}, ['paths', 'kind', 'reason'])
POLICY = obj({'version': {'const': 1}, 'rules': {'type': 'array', 'items': RULE}}, ['version', 'rules'])


def policy(root):
    path = root/'verification/impact.json'
    if not path.exists():
        return {'version': 1, 'rules': []}
    result = json.loads(path.read_text())
    fastjsonschema.validate(POLICY, result)
    for rule in result['rules']:
        if rule['kind'] == 'owners' and not rule.get('cores'):
            raise ValueError('Impact owner rules require explicit core names')
        if rule['kind'] != 'owners' and rule.get('cores'):
            raise ValueError('Only owner rules may name cores')
    return result


def rules_for(configuration, path):
    return [rule for rule in configuration['rules'] if any(fnmatch.fnmatchcase(path, pattern) for pattern in rule['paths'])]


def add_inputs(root, cores, files):
    """Register inputs without hash validation; selected suites validate before execution."""
    errors = []
    def own(path, name):
        files.setdefault(inside(root, path), set()).add(name)
    for name, core in sorted(cores.items()):
        config = core.get_validation() or {}
        for test in config.get('tests', {}).values():
            if not test.get('manifest'):
                continue
            path = inside(root, test['manifest'])
            own(path, name)
            own(path.parent, name)
            try:
                manifest = json.loads(path.read_text())
                for item in manifest['tests']:
                    own(path.parent/item['file'], name)
                if manifest.get('config_directory'):
                    own(path.parent/manifest['config_directory'], name)
                for item in manifest.get('config_sha256', {}):
                    own(path.parent/manifest['config_directory']/item, name)
            except (OSError, ValueError, KeyError) as exc:
                errors.append(f'{name}: cannot resolve firmware inputs: {exc}')
    for path in sorted((root/'platforms').glob('*/platform.json')):
        try:
            data = json.loads(path.read_text())
            name = data.get('hardware_core')
            if not name:
                continue
            if name not in cores:
                errors.append(f'{path.relative_to(root)}: unknown hardware_core {name}')
                continue
            own(path, name)
            own(path.parent, name)
            for key in ('memory_contract', 'memory_implementation', 'firmware_linker',
                        'architecture_test_config', 'architecture_test_manifest', 'firmware_test_manifest'):
                if data.get(key):
                    own(data[key], name)
        except (OSError, ValueError, KeyError) as exc:
            errors.append(f'{path.relative_to(root)}: cannot resolve platform inputs: {exc}')
    return errors


def flag_variants(core):
    """Resolve all Boolean variants referenced by CAPI conditional expressions.

    Bound expansion: larger or unsupported graphs must be reported incomplete,
    never silently interpreted as a narrower dependency graph.
    """
    names = set()
    def conditions(ast):
        for node in ast:
            if not isinstance(node, str):
                names.add(node[1])
                conditions(node[2])
    def visit(value):
        if isinstance(value, dict):
            for key, item in value.items():
                visit(key)
                visit(item)
        elif isinstance(value, list):
            for item in value:
                visit(item)
        elif isinstance(value, str) and '?' in value:
            conditions(Exprs(value).ast)
    for section in ('filesets', 'targets'):
        visit(core._capi_data.get(section, {}))
    names = sorted(names)
    if len(names) > 8:
        raise ValueError('More than eight conditional flags; declare smaller validation configurations')
    return [dict(zip(names, values)) for values in itertools.product((False, True), repeat=len(names))]
