# SPDX-License-Identifier: Apache-2.0
"""Select per-core smoke suites from resolved FuseSoC consumer dependencies."""
import argparse
from collections import deque
from datetime import datetime, timezone
from pathlib import Path
import subprocess
import signal
import uuid

from fusesoc.coremanager import DependencyError

from .model import expand, validate, validate_parameters, tree_identity
from .report import save
from .impact_inputs import add_inputs, flag_variants, policy as impact_policy, rules_for


def changed_paths(root, base):
    """Include committed, staged, unstaged, deleted, renamed and untracked files."""
    merge_base = subprocess.check_output(
        ['git', 'merge-base', 'HEAD', base], cwd=root, text=True).strip()
    changed = subprocess.check_output(
        ['git', 'diff', '--name-only', '--no-renames', '-z', merge_base, '--'], cwd=root)
    untracked = subprocess.check_output(
        ['git', 'ls-files', '--others', '--exclude-standard', '-z'], cwd=root)
    return merge_base, sorted(set(p for p in (changed + untracked).decode().split('\0') if p))


def inventory(fs):
    """Union declared target graphs, resolving versions/providers with FuseSoC.

    Snapshot direct_deps immediately: the solver mutates Core objects between
    resolutions. Unioning targets deliberately favors extra consumers over gaps.
    """
    cores = fs.get_cores()
    # Solver cache holds mutable Core objects; start fresh before snapshotting.
    fs.cm.db._solver_cache_invalidate_all()
    edges = {name: set() for name in cores}
    files = {}
    errors = []
    for name, core in sorted(cores.items()):
        files.setdefault(Path(core.core_file).resolve(), set()).add(name)
        try:
            variants = flag_variants(core)
        except ValueError as exc:
            errors.append(f'{name}: {exc}')
            variants = [{}]
        for target in sorted(core._capi_data.get('targets', {})):
            for variant in variants:
                try:
                    flags = dict(core.get_flags(target), **variant)
                    flags.update(target=target, is_toplevel=True)
                    resolved = fs.cm.get_depends(core.name, flags)
                    for dependency in resolved:
                        dep_name = str(dependency.name)
                        edges.setdefault(dep_name, set()).update(dependency.direct_deps)
                        effective = dict(flags, is_toplevel=dep_name == name)
                        for source in dependency.get_files(effective):
                            path = (Path(dependency.files_root) / source['name']).resolve()
                            files.setdefault(path, set()).add(dep_name)
                    if core.get_ttptttg(flags):
                        errors.append(f'{name}/{target}: generated dependency graph is unresolved before setup')
                except (DependencyError, RuntimeError, ValueError, SyntaxError, KeyError) as exc:
                    errors.append(f'{name}/{target}/{variant}: {exc}')
    registered = {Path(core.core_file).resolve() for core in cores.values()}
    ignored = set(fs.config.ignored_dirs)
    for library in fs.get_libraries():
        for path in Path(library.location).rglob('*.core'):
            if not any(part in ignored for part in path.parts) and path.resolve() not in registered:
                errors.append(f'{path}: core was not registered (parse error, duplicate or unsupported provider)')
    return cores, edges, files, sorted(set(errors))


def consumer_paths(edges, owner):
    reverse = {}
    for consumer, dependencies in edges.items():
        for dependency in dependencies:
            reverse.setdefault(dependency, set()).add(consumer)
    paths = {owner: [owner]}
    pending = deque([owner])
    while pending:
        node = pending.popleft()
        for consumer in sorted(reverse.get(node, [])):
            if consumer not in paths:
                paths[consumer] = paths[node] + [consumer]
                pending.append(consumer)
    return paths


def select(fs, root, paths, suite='smoke', full=False):
    cores, edges, files, errors = inventory(fs)
    errors.extend(add_inputs(root, cores, files))
    configuration = impact_policy(root)
    for rule in configuration['rules']:
        for name in rule.get('cores', []):
            if name not in cores:
                raise ValueError(f'Impact rule names unknown core {name}')
    reasons = {}
    unknown = []
    classifications = []
    global_paths = []
    for changed in sorted(set(paths)):
        absolute = (root / changed).resolve()
        owners = set(files.get(absolute, set()))
        for parent in absolute.parents:
            owners.update(files.get(parent, set()))
        matches = rules_for(configuration, changed)
        for rule in matches:
            owners.update(rule.get('cores', []))
        if not owners and any(rule['kind'] == 'global' for rule in matches):
            global_paths.append(changed)
            classifications.append({'path': changed, 'kind': 'global', 'rules': matches})
            continue
        if not owners and any(rule['kind'] == 'documentation' for rule in matches):
            classifications.append({'path': changed, 'kind': 'documentation', 'rules': matches})
            continue
        if not owners:
            # Covers deleted files and IP-local manifests/configuration without
            # maintaining a second source list. Nested owners are conservative.
            owners = {name for name, core in cores.items()
                      if absolute.is_relative_to(Path(core.core_root).resolve())}
        if not owners:
            unknown.append(changed)
        classifications.append({'path': changed, 'kind': 'owned' if owners else 'unknown', 'owners': sorted(owners)})
        for owner in sorted(owners):
            for consumer, chain in consumer_paths(edges, owner).items():
                reasons.setdefault(consumer, []).append({'changed_path': changed, 'dependency_path': chain})
    fallback = []
    if full:
        fallback.append('Explicit --full selection')
    if unknown:
        fallback.append('Unclassified paths: ' + ', '.join(unknown))
    if global_paths:
        fallback.append('Shared inputs: ' + ', '.join(global_paths))
    if errors and paths:
        fallback.append('Incomplete dependency graph; see graph_errors')
    if fallback:
        for name in sorted(cores):
            reasons.setdefault(name, []).extend({'fallback': reason} for reason in fallback)
    selected = []
    missing = []
    for name, why in sorted(reasons.items()):
        core = cores[name]
        config = core.get_validation()
        if not config or suite not in config['regressions']:
            missing.append({'core': name, 'suite': suite, 'reasons': why, 'qualification': 'missing_suite'})
            continue
        validate(config, core._capi_data['targets'])
        from .model import inputs
        for definition in config['tests'].values():
            inputs(root, definition)
        jobs = expand(root, config, suite)
        validate_parameters(core, config, jobs)
        selected.append({'core': name, 'suite': suite, 'reasons': why,
                         'jobs': jobs, 'job_count': len(jobs)})
    return {'schema_version': 1, 'changed_paths': sorted(set(paths)),
            'classifications': classifications, 'policy': configuration,
            'selection_complete': not errors,
            'suite': suite, 'selected': selected, 'missing_suites': missing,
            'graph_errors': errors, 'fallback_reasons': fallback,
            'dependencies': {k: sorted(v) for k, v in sorted(edges.items())},
            'job_count': sum(item['job_count'] for item in selected)}


def invoke(fs, args):
    from .engine import campaign
    root = Path(fs.config._path).resolve().parent
    try:
        if args.jobs is not None and args.jobs < 1:
            raise ValueError('--jobs must be positive')
        if args.timeout is not None and args.timeout < 1:
            raise ValueError('--timeout must be positive')
        source_identity = tree_identity(root)
        merge_base, paths = changed_paths(root, args.base)
        plan = select(fs, root, paths, args.suite, args.full)
        plan.update(base=args.base, merge_base=merge_base,
                    revision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
                    source_tree_sha256=source_identity)
        if tree_identity(root) != source_identity:
            raise RuntimeError('Sources changed during selection; rerun presubmit')
        directory = root/'artifacts'/'impact'/(datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S')+'-'+uuid.uuid4().hex[:8])
        directory.mkdir(parents=True)
        manifest = directory/'selection.json'
        plan['status'] = 'BLOCKED' if plan['missing_suites'] or (paths and plan['graph_errors']) else 'PLANNED'
        save(manifest, plan)
        lines = [f"Selected {len(plan['selected'])} cores, {plan['job_count']} jobs ({args.suite})"]
        for item in plan['selected']:
            lines.append(f"{item['core']}: {item['job_count']} jobs")
            for why in item['reasons']:
                lines.append('  '+(why.get('fallback') or why['changed_path']+': '+' -> '.join(why['dependency_path'])))
        for item in plan['missing_suites']:
            lines.append(f"BLOCKED: {item['core']} has no {args.suite} suite")
        for error in plan['graph_errors']:
            lines.append(f'GRAPH GAP: {error}')
        for item in plan['classifications']:
            if item['kind'] == 'documentation': lines.append(f"Documentation only: {item['path']}")
        lines.append(f'Selection: {manifest}')
        (directory/'selection.txt').write_text('\n'.join(lines)+'\n')
        print('\n'.join(lines), flush=True)
        if plan['status'] == 'BLOCKED':
            return 2
        if args.dry_run:
            return 0
        if not plan['selected']:
            docs_only = all(item['kind'] == 'documentation' for item in plan['classifications'])
            plan['status'] = 'NO_CHANGES' if not paths else ('NO_HARDWARE_CHANGES' if docs_only else 'BLOCKED')
            save(manifest, plan)
            return 0 if docs_only else 2
        plan['status'] = 'RUNNING'
        save(manifest, plan)
        failed = False
        for item in plan['selected']:
            if tree_identity(root) != source_identity:
                raise RuntimeError('Sources changed after selection; rerun presubmit')
            # Existing campaign execution owns subprocess cancellation and artifacts.
            options = argparse.Namespace(core=item['core'], suite=args.suite, test=None,
                seed=None, run_mode=None, jobs=args.jobs, timeout=args.timeout,
                list=False, dry_run=False, action='regress', no_cache=getattr(args, 'no_cache', False),
                impact={'selection_manifest': str(manifest), 'merge_base': merge_base,
                        'reasons': item['reasons']})
            result = campaign(fs, options)
            item['exit_status'] = result
            item['campaign_manifest'] = getattr(options, 'campaign_manifest', None)
            failed |= result != 0
            save(manifest, plan)
            if getattr(options, 'campaign_status', None) == 'CANCELLED':
                plan['status'] = 'CANCELLED'
                save(manifest, plan)
                return 130
        if tree_identity(root) != source_identity:
            raise RuntimeError('Sources changed during execution; rerun presubmit')
        plan['status'] = 'FAIL' if failed else 'PASS'
        save(manifest, plan)
        return int(failed)
    except (ValueError, RuntimeError, OSError, subprocess.CalledProcessError) as exc:
        if 'plan' in locals() and 'manifest' in locals():
            plan.update(status='FAIL', error=str(exc))
            save(manifest, plan)
        print(f'Impact error: {exc}')
        return 2
    except KeyboardInterrupt:
        if 'plan' in locals() and 'manifest' in locals():
            plan['status'] = 'CANCELLED'
            save(manifest, plan)
        return 130


def register(subparsers):
    parser = subparsers.add_parser('presubmit', help='Run smoke suites for changed cores and their consumers')
    parser.add_argument('--base', required=True, help='Git reference used to compute the merge base')
    parser.add_argument('--suite', default='smoke', help='Per-core regression to select (default: smoke)')
    parser.add_argument('--full', action='store_true', help='Select every core with validation declarations')
    parser.add_argument('--dry-run', action='store_true', help='Retain and print selection without building')
    parser.add_argument('--no-cache', action='store_true')
    parser.add_argument('--jobs', type=int)
    parser.add_argument('--timeout', type=int)
    parser.set_defaults(func=command)


def command(fs, args):
    def interrupt(*_):
        raise KeyboardInterrupt
    previous = {sig: signal.signal(sig, interrupt) for sig in (signal.SIGINT, signal.SIGTERM)}
    try:
        raise SystemExit(invoke(fs, args))
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)
