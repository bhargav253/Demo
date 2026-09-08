#!/usr/bin/env python3
"""Legacy composed per-IP gate. FuseSoC owns every HDL source list."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
import json
import math
import signal
import threading
import shlex
import subprocess
import sys
import uuid

from evidence import provenance, save
from run_target import REPO_ROOT, SAFE_PART, FULL_VLNV, core_info, target_names


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--core', required=True)
    parser.add_argument('--seed-count', type=int, default=100)
    parser.add_argument('--jobs', type=int, default=8)
    parser.add_argument('--cycles', type=int, default=200)
    parser.add_argument('--timeout', type=float, default=600)
    args = parser.parse_args()
    if not math.isfinite(args.timeout) or not FULL_VLNV.fullmatch(args.core) or min(args.seed_count, args.jobs, args.cycles, args.timeout) <= 0:
        parser.error('full VLNV and positive limits required')
    profiles = json.loads((REPO_ROOT / 'verification/ip_checks.json').read_text())
    if args.core not in profiles:
        parser.error('core has no reviewed check profile in verification/ip_checks.json')
    profile = profiles[args.core]
    available = target_names(core_info(args.core))
    required = ['lint', 'sim', *profile['formal_targets'], *profile.get('simulation_targets', [])]
    if not set(required) <= available:
        parser.error(f'missing required targets: {set(required)-available}')
    run_id = datetime.now(UTC).strftime('%Y%m%dT%H%M%S') + '-' + uuid.uuid4().hex[:8]
    directory = REPO_ROOT / 'artifacts' / SAFE_PART.sub('_', args.core) / 'check-ip' / run_id
    directory.mkdir(parents=True)
    command = [sys.executable, str(REPO_ROOT / 'tools/build/check_ip.py'), *sys.argv[1:]]
    data = dict(provenance(REPO_ROOT), core=args.core, result='RUNNING', runs=[],
                profile=profile, rerun_command=shlex.join(command))
    save(directory / 'run.json', data)
    cancelled = threading.Event()
    active = set()
    active_lock = threading.Lock()
    def interrupt(signum, frame):
        cancelled.set()
        with active_lock:
            for process in active:
                try:
                    process.send_signal(signal.SIGTERM)
                except ProcessLookupError:
                    pass
    previous = {sig:signal.signal(sig, interrupt) for sig in (signal.SIGINT, signal.SIGTERM)}
    def run(action, target, test=None, seed=1, skip=False):
        cmd = [sys.executable, str(REPO_ROOT / 'tools/build/run_target.py'), action,
               '--core', args.core, '--target', target, '--timeout', str(args.timeout)]
        if test:
            cmd += ['--test', test, '--seed', str(seed), '--cycles', str(args.cycles)]
        if skip:
            cmd += ['--skip-build']
        with active_lock:
            if cancelled.is_set():
                return {'command':cmd, 'exit_status':130, 'report':'', 'output':'Cancelled before launch'}
            p = subprocess.Popen(cmd, cwd=REPO_ROOT, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, text=True, start_new_session=True)
            active.add(p)
        output, _ = p.communicate()
        with active_lock:
            active.discard(p)
        report = next((line[8:] for line in output.splitlines() if line.startswith('Report: ')), '')
        print(f'{target} {test or ""} seed={seed}: {"PASS" if p.returncode == 0 else "FAIL"} {report}', flush=True)
        child_manifest = REPO_ROOT / report
        child_manifest = child_manifest.parent / 'run.json'
        evidence = json.loads(child_manifest.read_text()) if report and child_manifest.is_file() else {}
        return {'command':cmd, 'exit_status':p.returncode, 'report':report,
                'target':target, 'executable_sha256':evidence.get('executable_sha256'),
                'output':output if p.returncode else ''}
    try:
        for action, target, test in [('lint','lint',None),('sim','sim','directed')]:
            data['runs'].append(run(action,target,test))
            save(directory / 'run.json', data)
            if data['runs'][-1]['exit_status']:
                break
        if all(r['exit_status'] == 0 for r in data['runs']):
            with ThreadPoolExecutor(max_workers=args.jobs) as pool:
                for result in pool.map(lambda seed:run('sim','sim','random',seed,True), range(1,args.seed_count+1)):
                    data['runs'].append(result)
                    save(directory / 'run.json', data)
            for target in profile.get('simulation_targets', []):
                data['runs'].append(run('sim', target, 'directed'))
            for target in profile['formal_targets']:
                data['runs'].append(run('formal',target))
        data['result'] = 'PASS' if all(r['exit_status'] == 0 for r in data['runs']) else 'FAIL'
        identities = {}
        for run_record in data['runs']:
            if run_record.get('executable_sha256'):
                identities.setdefault(run_record['target'], set()).add(run_record['executable_sha256'])
        if any(len(values) > 1 for values in identities.values()):
            data['result'] = 'FAIL'
            data['error'] = 'Executable changed during campaign; rerun against stable sources'
    except KeyboardInterrupt:
        data['result'] = 'INTERRUPTED'
    finally:
        if cancelled.is_set():
            data['result'] = 'INTERRUPTED'
        for sig, handler in previous.items():
            signal.signal(sig, handler)
        save(directory / 'run.json', data)
    print(f"Result: {data['result']}\nManifest: {directory / 'run.json'}\nRerun: {data['rerun_command']}")
    return 0 if data['result'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
