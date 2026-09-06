#!/usr/bin/env python3
"""Build a FuseSoC ELF harness once, run prebuilt firmware, and retain evidence."""
from __future__ import annotations
import argparse
import concurrent.futures
import fcntl
import hashlib
import json
import shutil
import subprocess
import tempfile
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "build"))
from run_target import FUSESOC, REPO_ROOT, FULL_VLNV, SAFE_PART, find_simulator


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('elf', nargs='*', type=Path)
    parser.add_argument('--manifest', type=Path)
    parser.add_argument('--core', default='axon:core:riscv:0.1.0')
    parser.add_argument('--target', default='sim_fw')
    parser.add_argument('--cycles', type=int, default=1000000)
    parser.add_argument('--wait', type=int, default=0)
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--jobs', type=int, default=1)
    parser.add_argument('--waves', action='store_true')
    args = parser.parse_args()
    if not FULL_VLNV.fullmatch(args.core) or not args.target.startswith('sim'):
        parser.error('Expected full Axon VLNV and simulation target')
    if args.cycles < 1 or args.jobs < 1 or not 0 <= args.wait <= 1000 or args.seed < 0:
        parser.error('Invalid cycle/job/wait/seed value')
    elfs = [p.resolve(strict=True) for p in args.elf]
    manifest = None
    if args.manifest:
        manifest = json.loads(args.manifest.read_text())
        if 'config_sha256' in manifest:
            config_dir = args.manifest.parent / manifest['config_directory']
            for name, expected in manifest['config_sha256'].items():
                path = config_dir / name
                if not path.is_file() or sha(path) != expected:
                    parser.error(f'Platform configuration changed; regenerate binaries: {path}')
        for item in manifest['tests']:
            p = (args.manifest.parent / item['file']).resolve(strict=True)
            if sha(p) != item['sha256']:
                parser.error(f'Binary checksum mismatch: {p}')
            elfs.append(p)
    if not elfs:
        parser.error('Supply ELFs or a nonempty manifest')
    core = SAFE_PART.sub('_', args.core)
    target = SAFE_PART.sub('_', args.target)
    work = REPO_ROOT / 'build' / core / target
    root = REPO_ROOT / 'artifacts' / core / 'firmware'
    root.mkdir(parents=True, exist_ok=True)
    report = Path(tempfile.mkdtemp(prefix='run-', dir=root))
    build = [str(FUSESOC), 'run', '--build', '--target', args.target,
             '--work-root', str(work), args.core]
    work.parent.mkdir(parents=True, exist_ok=True)
    with (work.parent / f'.{target}.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        with (report / 'build.log').open('w') as log:
            status = subprocess.run(build, cwd=REPO_ROOT, stdout=log, stderr=subprocess.STDOUT).returncode
        simulator = find_simulator(work) if status == 0 else None
        if simulator is None:
            print(f'BUILD FAIL: {report / "build.log"}')
            return 1
        # Immutable executable copy prevents a concurrent build changing this campaign.
        executable = report / simulator.name
        shutil.copy2(simulator, executable)
    def run(pair):
        index, elf = pair
        directory = report / f'{index:04d}-{elf.stem}'
        directory.mkdir()
        image = directory / 'test.elf'
        shutil.copy2(elf, image)
        command = [str(executable), f'+ELF={image}', f'+CYCLES={args.cycles}',
                   f'+WAIT={args.wait}', f'+SEED={args.seed}', f'+TEST={elf.stem}']
        if args.waves:
            command.append(f'+WAVE={directory / "waves.fst"}')
        with (directory / 'sim.log').open('w') as log:
            try:
                code = subprocess.run(command, cwd=directory, stdout=log,
                                      stderr=subprocess.STDOUT, timeout=300).returncode
            except subprocess.TimeoutExpired:
                log.write('\nHost timeout after 300 seconds\n')
                code = 124
        result = {'elf': str(elf), 'sha256': sha(image), 'exit_status': code,
                  'result': 'PASS' if code == 0 else 'FAIL', 'command': command,
                  'log': str(directory / 'sim.log')}
        print(f'{result["result"]}: {elf.name}')
        return result
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        results = list(pool.map(run, enumerate(elfs)))
    def git(*cmd):
        return subprocess.check_output(['git', *cmd], cwd=REPO_ROOT, text=True).strip()
    evidence = {'core': args.core, 'target': args.target, 'revision': git('rev-parse', 'HEAD'),
                'dirty_status': git('status', '--porcelain'), 'build_command': build,
                'simulator_sha256': sha(executable),
                'verilator': subprocess.check_output(['verilator', '--version'], text=True).strip(),
                'seed': args.seed, 'wait': args.wait, 'cycles': args.cycles,
                'input_manifest': manifest, 'results': results}
    (report / 'results.json').write_text(json.dumps(evidence, indent=2)+'\n')
    print(f'Report: {report / "results.json"}')
    return int(any(r['exit_status'] != 0 for r in results))


if __name__ == '__main__':
    raise SystemExit(main())
