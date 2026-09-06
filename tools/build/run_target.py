#!/usr/bin/env python3
"""Validate and run stable Axon FuseSoC targets."""

from __future__ import annotations

import argparse
import fcntl
import os
import re
import shlex
import subprocess
import sys
import tempfile
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
    process = subprocess.Popen(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=1,
    )
    assert process.stdout is not None
    for line in process.stdout:
        print(line, end="", flush=True)
        log_file.write(line)
    return process.wait()


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


def run_lint(core: str, target: str, work_root: Path) -> int:
    command = [
        str(FUSESOC),
        "run",
        "--clean",
        "--target",
        target,
        "--work-root",
        str(work_root),
        core,
    ]
    work_root.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        prefix=f".{target}-",
        suffix=".log.tmp",
        dir=work_root.parent,
        delete=False,
    ) as log_file:
        temporary_log = Path(log_file.name)
        log_file.write(f"Core: {core}\nTarget: {target}\n")
        log_file.write(f"Command: {shlex.join(command)}\n\n")
        return_code = stream_command(command, REPO_ROOT, log_file)
        result = "PASS" if return_code == 0 else "FAIL"
        write_result(log_file, result, return_code)

    work_root.mkdir(parents=True, exist_ok=True)
    report = work_root / "lint.log"
    temporary_log.replace(report)
    print(f"Result: {result}", flush=True)
    print(f"Report: {report.relative_to(REPO_ROOT)}", flush=True)
    return return_code


def run_sim(
    core: str,
    target: str,
    test: str,
    seed: int,
    cycles: int,
    rebuild: bool,
    skip_build: bool,
    work_root: Path,
) -> int:
    safe_core = SAFE_PART.sub("_", core)
    safe_test = SAFE_PART.sub("_", test)
    timestamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%S.%fZ")
    run_id = f"{timestamp}-{os.getpid()}-{uuid.uuid4().hex[:8]}"
    report_dir = (
        REPO_ROOT
        / "artifacts"
        / safe_core
        / target
        / safe_test
        / f"seed-{seed}"
        / run_id
    )
    report_dir.mkdir(parents=True, exist_ok=False)
    temporary_report = report_dir / ".sim.log.tmp"
    report = report_dir / "sim.log"

    build_command = [str(FUSESOC), "run"]
    if rebuild:
        build_command.append("--clean")
    build_command += [
        "--build",
        "--target",
        target,
        "--work-root",
        str(work_root),
        core,
    ]

    work_root.parent.mkdir(parents=True, exist_ok=True)
    lock_path = work_root.parent / f".{target}.lock"
    with temporary_report.open("w", encoding="utf-8") as log_file:
        log_file.write(f"Core: {core}\nTarget: {target}\n")
        log_file.write(f"Test: {test}\nSeed: {seed}\n")
        log_file.write(f"Cycles: {cycles}\n")
        log_file.write(f"Forced rebuild: {'yes' if rebuild else 'no'}\n")
        log_file.write(f"Build command: {shlex.join(build_command)}\n\n")

        if skip_build:
            simulator = find_simulator(work_root)
            build_status = 0
            before_mtime = simulator.stat().st_mtime_ns if simulator else None
            after_mtime = before_mtime
            log_file.write("Build check: skipped by prepared regression\n")
        else:
            with lock_path.open("w", encoding="utf-8") as lock_file:
                print(f"Build lock: {lock_path.relative_to(REPO_ROOT)}", flush=True)
                fcntl.flock(lock_file, fcntl.LOCK_EX)
                simulator_before = find_simulator(work_root)
                before_mtime = (
                    simulator_before.stat().st_mtime_ns if simulator_before else None
                )
                build_status = stream_command(build_command, REPO_ROOT, log_file)
                simulator = find_simulator(work_root)
                after_mtime = simulator.stat().st_mtime_ns if simulator else None
                fcntl.flock(lock_file, fcntl.LOCK_UN)

        if build_status != 0 or simulator is None:
            result = "FAIL"
            reuse = "FAILED"
            return_code = build_status if build_status != 0 else 1
            log_file.write(f"\nBuild result: {reuse}\n")
            if simulator is None:
                message = f"error: no unique simulator executable found in {work_root}"
                print(message, file=sys.stderr)
                log_file.write(f"\n{message}\n")
        else:
            reuse = "REUSED" if before_mtime == after_mtime else "BUILT"
            run_command = [
                str(simulator),
                f"+TEST={test}",
                f"+SEED={seed}",
                f"+CYCLES={cycles}",
            ]
            log_file.write(f"\nBuild result: {reuse}\n")
            log_file.write(f"Run command: {shlex.join(run_command)}\n\n")
            print(f"Build result: {reuse}", flush=True)
            return_code = stream_command(run_command, work_root, log_file)
            result = "PASS" if return_code == 0 else "FAIL"

        write_result(log_file, result, return_code)

    temporary_report.replace(report)
    print(f"Result: {result}", flush=True)
    print(f"Report: {report.relative_to(REPO_ROOT)}", flush=True)
    return return_code


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run an Axon target through repository-local FuseSoC"
    )
    parser.add_argument("action", choices=("lint", "sim"))
    parser.add_argument("--core", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--test")
    parser.add_argument("--seed", type=int)
    parser.add_argument("--cycles", type=int, default=200)
    parser.add_argument("--rebuild", action="store_true")
    parser.add_argument("--skip-build", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()

    core = args.core.strip()
    target = args.target.strip()
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

    if args.action == "lint":
        return run_lint(core, target, work_root)
    return run_sim(
        core,
        target,
        args.test,
        args.seed,
        args.cycles,
        args.rebuild,
        args.skip_build,
        work_root,
    )


if __name__ == "__main__":
    raise SystemExit(main())
