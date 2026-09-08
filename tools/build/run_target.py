#!/usr/bin/env python3
"""Validate and run stable Axon FuseSoC targets."""

from __future__ import annotations

import argparse
import fcntl
import math
import os
import re
import shlex
import subprocess
import sys
import shutil
import signal
import time
from evidence import digest, execute, provenance, save
import uuid
from datetime import UTC, datetime
from pathlib import Path
from typing import TextIO


REPO_ROOT = Path(__file__).resolve().parents[2]
FUSESOC = REPO_ROOT / "tools" / "bin" / "fusesoc"
FULL_VLNV = re.compile(
    r"^axon:[A-Za-z0-9_.+-]+:[A-Za-z0-9_.+-]+:[A-Za-z0-9_.+-]+$"
)
SAFE_PART = re.compile(r"[^A-Za-z0-9_.-]+")


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(2)


def core_info(core: str) -> str:
    result = subprocess.run(
        [str(FUSESOC), "core", "show", core],
        cwd=REPO_ROOT,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if result.returncode:
        detail = result.stdout.strip().splitlines()
        suffix = f" ({detail[-1]})" if detail else ""
        fail(f"FuseSoC core not found: {core}{suffix}")
    return result.stdout


def target_names(info: str) -> set[str]:
    targets: set[str] = set()
    in_targets = False
    for line in info.splitlines():
        if line.strip() == "Targets:":
            in_targets = True
            continue
        if in_targets:
            if not line.strip():
                continue
            match = re.match(r"^([A-Za-z0-9_.+-]+)\s+:", line)
            if not match:
                break
            targets.add(match.group(1))
    return targets


def stream_command(command: list[str], cwd: Path, log_file: TextIO) -> int:
    return execute(command, cwd, log_file, echo=True)


def find_simulator(work_root: Path) -> Path | None:
    candidates = sorted(
        path
        for path in work_root.glob("V*")
        if path.is_file() and os.access(path, os.X_OK) and "." not in path.name
    )
    return candidates[0] if len(candidates) == 1 else None


def write_result(log_file: TextIO, result: str, return_code: int) -> None:
    log_file.write(f"\nRESULT: {result}\n")
    log_file.write(f"Exit status: {return_code}\n")


def run_target(args) -> int:
    core, target = args.core, args.target
    run_id = datetime.now(UTC).strftime("%Y%m%dT%H%M%S.%fZ") + "-" + uuid.uuid4().hex[:8]
    report_dir = (REPO_ROOT / "artifacts" / SAFE_PART.sub("_", core) / target /
                  SAFE_PART.sub("_", args.test or "default") / f"seed-{args.seed or 0}" / run_id)
    report_dir.mkdir(parents=True)
    work_root = REPO_ROOT / "build" / SAFE_PART.sub("_", core) / target
    work_root.parent.mkdir(parents=True, exist_ok=True)
    # Formal runs own their working files so witnesses survive subsequent runs.
    if args.action == "formal":
        work_root = report_dir / "formal-work"
    rerun = [sys.executable, str(Path(__file__).resolve()), args.action,
             "--core", core, "--target", target, "--timeout", str(args.timeout)]
    if args.action == "sim":
        rerun += ["--test", args.test, "--seed", str(args.seed), "--cycles", str(args.cycles)]
    rerun += ["--max-log-mib", str(args.max_log_mib), "--max-wave-mib", str(args.max_wave_mib)]
    if args.rebuild:
        rerun.append("--rebuild")
    manifest = dict(provenance(REPO_ROOT), core=core, target=target, test=args.test,
                    seed=args.seed, parameters={"CYCLES":args.cycles} if args.action == "sim" else {},
                    result="RUNNING", rerun_command=shlex.join(rerun), commands=[],
                    timeout_seconds=args.timeout, max_log_mib=args.max_log_mib,
                    max_wave_mib=args.max_wave_mib, started_at=datetime.now(UTC).isoformat())
    save(report_dir / "run.json", manifest)
    report = report_dir / ("sim.log" if args.action == "sim" else target + ".log")
    code = 1
    previous_handlers = {}
    def interrupt(signum, frame):
        raise KeyboardInterrupt
    for sig in (signal.SIGINT, signal.SIGTERM):
        previous_handlers[sig] = signal.signal(sig, interrupt)
    def call(command, cwd, log, simulation=False):
        manifest['commands'].append({'argv':command, 'cwd':str(cwd)})
        save(report_dir / "run.json", manifest)
        return execute(command, cwd, log, args.timeout, args.max_log_mib*1024*1024,
                       args.max_wave_mib*1024*1024 if simulation else 1024*1024*1024)
    try:
        with report.open('w') as log:
            command = [str(FUSESOC), 'run']
            if args.rebuild:
                command.append('--clean')
            if args.action == 'sim':
                command.append('--build')
            command += ['--target', target, '--work-root', str(work_root), core]
            lock = work_root.parent / ('.' + target + '.lock')
            with lock.open('w') as handle:
                deadline = time.monotonic() + args.timeout
                while True:
                    try:
                        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        break
                    except BlockingIOError:
                        if time.monotonic() >= deadline:
                            raise TimeoutError('build lock timeout')
                        time.sleep(.1)
                before = find_simulator(work_root)
                before_hash = digest(before) if before else None
                code = 0 if args.skip_build else call(command, REPO_ROOT, log)
                manifest['build_metadata'] = {str(p.relative_to(work_root)):digest(p)
                    for p in work_root.rglob('*') if p.is_file() and p.suffix in ('.yml', '.vc', '.sv', '.svh', '.v', '.cpp', '.sby')}
                for metadata in work_root.glob('*.eda.yml'):
                    shutil.copy2(metadata, report_dir / metadata.name)
                if code == 0 and args.action == 'sim':
                    simulator = find_simulator(work_root)
                    if simulator is None:
                        raise RuntimeError('no unique simulator executable after build')
                    manifest['executable_sha256'] = digest(simulator)
                    manifest['build_result'] = 'REUSED' if before_hash == manifest['executable_sha256'] else 'BUILT'
                    # Copy while holding the build lock; another build cannot change this run.
                    snapshot = report_dir / simulator.name
                    shutil.copy2(simulator, snapshot)
            if code == 0 and args.action == 'sim':
                command = [str(snapshot), f'+TEST={args.test}', f'+SEED={args.seed}',
                           f'+CYCLES={args.cycles}', '+AXON_WAVE_FILE=waves.fst']
                code = call(command, report_dir, log, simulation=True)
                snapshot.unlink()
            write_result(log, 'PASS' if code == 0 else 'FAIL', code)
    except KeyboardInterrupt:
        code = 130
    except TimeoutError as exc:
        code = 124
        manifest['error'] = str(exc)
    except (OSError, RuntimeError) as exc:
        manifest['error'] = str(exc)
        code = 1
    for sig, handler in previous_handlers.items():
        signal.signal(sig, handler)
    manifest['result'] = {0:'PASS',124:'TIMEOUT',125:'OUTPUT_LIMIT',130:'INTERRUPTED'}.get(code, 'FAIL')
    manifest['exit_status'] = code
    manifest['finished_at'] = datetime.now(UTC).isoformat()
    if code == 0:
        (report_dir / 'waves.fst').unlink(missing_ok=True)
        # Keep a concise tail for successful tool chatter.
        lines = report.read_text(errors='replace').splitlines()
        report.write_text('\n'.join(lines[-60:]) + '\n')
    manifest['artifacts'] = [str(p.relative_to(report_dir)) for p in report_dir.rglob('*') if p.is_file()]
    save(report_dir / 'run.json', manifest)
    print(f"Result: {manifest['result']}")
    print(f"Report: {report.relative_to(REPO_ROOT)}")
    print(f"Rerun: {manifest['rerun_command']}")
    return code if code >= 0 else 128 - code


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run an Axon target through repository-local FuseSoC"
    )
    parser.add_argument("action", choices=("lint", "sim", "formal"))
    parser.add_argument("--core", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--test")
    parser.add_argument("--seed", type=int)
    parser.add_argument("--cycles", type=int, default=200)
    parser.add_argument("--rebuild", action="store_true")
    parser.add_argument("--skip-build", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--timeout", type=float, default=600)
    parser.add_argument("--max-log-mib", type=int, default=2)
    parser.add_argument("--max-wave-mib", type=int, default=32)
    args = parser.parse_args()
    if not math.isfinite(args.timeout) or args.timeout <= 0 or args.max_log_mib < 1 or args.max_wave_mib < 1:
        fail("timeout and output limits must be positive")
    if args.action == 'formal' and not args.target.startswith('formal'):
        fail("formal requires a formal target")

    core = args.core = args.core.strip()
    target = args.target = args.target.strip()
    if not core:
        fail("CORE is required; for example, "
             "make lint CORE=axon:noc:islip_arbiter:0.1.0")
    if not FULL_VLNV.fullmatch(core):
        fail("CORE must be a complete axon:<library>:<name>:<version> VLNV")
    if not target:
        fail("TARGET must not be empty")
    if args.action == "lint" and not target.startswith("lint"):
        fail(f"lint may only invoke a lint target, not '{target}'")
    if args.action == "sim" and not target.startswith("sim"):
        fail(f"sim may only invoke a sim target, not '{target}'")
    if args.action == "sim" and not args.test:
        fail("TEST is required for simulation")
    if args.action == "sim" and (args.seed is None or args.seed < 0):
        fail("SEED must be a non-negative integer for simulation")
    if args.action == "sim" and args.cycles < 1:
        fail("CYCLES must be a positive integer for simulation")
    if args.skip_build and args.action != 'sim':
        fail('--skip-build is only valid for prepared simulation runs')
    if args.rebuild and args.skip_build:
        fail("--rebuild and --skip-build cannot be used together")

    available = target_names(core_info(core))
    if target not in available:
        choices = ", ".join(sorted(available)) or "none"
        fail(f"core {core} has no target '{target}' (available: {choices})")

    safe_core = SAFE_PART.sub("_", core)
    safe_target = SAFE_PART.sub("_", target)
    work_root = REPO_ROOT / "build" / safe_core / safe_target
    print(f"Axon {args.action}: {core} target={target}", flush=True)
    print(f"Build directory: {work_root.relative_to(REPO_ROOT)}", flush=True)

    return run_target(args)


if __name__ == "__main__":
    raise SystemExit(main())
