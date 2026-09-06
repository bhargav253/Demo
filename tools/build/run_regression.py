#!/usr/bin/env python3
"""Build once and run an Axon simulation across a bounded seed pool."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import subprocess
import sys
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import UTC, datetime
from pathlib import Path

from run_target import (
    FULL_VLNV,
    FUSESOC,
    REPO_ROOT,
    SAFE_PART,
    core_info,
    find_simulator,
    stream_command,
    target_names,
)


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(2)


def run_seed(
    core: str, target: str, test: str, seed: int, cycles: int
) -> dict[str, object]:
    command = [
        sys.executable,
        str(REPO_ROOT / "tools" / "build" / "run_target.py"),
        "sim",
        "--core",
        core,
        "--target",
        target,
        "--test",
        test,
        "--seed",
        str(seed),
        "--cycles",
        str(cycles),
        "--skip-build",
    ]
    completed = subprocess.run(
        command,
        cwd=REPO_ROOT,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    report = ""
    for line in completed.stdout.splitlines():
        if line.startswith("Report: "):
            report = line.removeprefix("Report: ")
    return {
        "seed": seed,
        "result": "PASS" if completed.returncode == 0 else "FAIL",
        "exit_status": completed.returncode,
        "report": report,
        "output": completed.stdout,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build one simulator and run a deterministic seed regression"
    )
    parser.add_argument("--core", required=True)
    parser.add_argument("--target", default="sim")
    parser.add_argument("--test", default="random")
    parser.add_argument("--seed-start", type=int, default=1)
    parser.add_argument("--seed-count", type=int, default=1)
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--cycles", type=int, default=200)
    parser.add_argument("--rebuild", action="store_true")
    args = parser.parse_args()

    core = args.core.strip()
    target = args.target.strip()
    test = args.test.strip()
    if not FULL_VLNV.fullmatch(core):
        fail("CORE must be a complete axon:<library>:<name>:<version> VLNV")
    if not target.startswith("sim"):
        fail("TARGET must name a simulation target")
    if not test:
        fail("TEST must not be empty")
    if args.seed_start < 0:
        fail("SEED_START must be non-negative")
    if args.seed_count < 1:
        fail("SEED_COUNT must be positive")
    if args.jobs < 1:
        fail("JOBS must be positive")
    if args.cycles < 1:
        fail("CYCLES must be positive")

    available = target_names(core_info(core))
    if target not in available:
        choices = ", ".join(sorted(available)) or "none"
        fail(f"core {core} has no target '{target}' (available: {choices})")

    safe_core = SAFE_PART.sub("_", core)
    safe_target = SAFE_PART.sub("_", target)
    safe_test = SAFE_PART.sub("_", test)
    work_root = REPO_ROOT / "build" / safe_core / safe_target
    timestamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%S.%fZ")
    regression_id = f"{timestamp}-{os.getpid()}-{uuid.uuid4().hex[:8]}"
    report_dir = (
        REPO_ROOT / "artifacts" / safe_core / "regress" / safe_test / regression_id
    )
    report_dir.mkdir(parents=True, exist_ok=False)
    regression_log = report_dir / "regression.log"
    results_file = report_dir / "results.json"

    build_command = [str(FUSESOC), "run"]
    if args.rebuild:
        build_command.append("--clean")
    build_command += [
        "--build",
        "--target",
        target,
        "--work-root",
        str(work_root),
        core,
    ]

    print(f"Axon regression: {core} test={test}")
    print(
        f"Seeds: {args.seed_start}..{args.seed_start + args.seed_count - 1} "
        f"jobs={args.jobs} cycles={args.cycles}"
    )
    work_root.parent.mkdir(parents=True, exist_ok=True)
    lock_path = work_root.parent / f".{target}.lock"
    with regression_log.open("w", encoding="utf-8") as log_file:
        log_file.write(f"Core: {core}\nTarget: {target}\nTest: {test}\n")
        log_file.write(
            f"Seed start: {args.seed_start}\nSeed count: {args.seed_count}\n"
            f"Jobs: {args.jobs}\nCycles: {args.cycles}\n\n"
        )
        with lock_path.open("w", encoding="utf-8") as lock_file:
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
            log_file.write("\nBuild result: FAILED\nRESULT: FAIL\n")
            print("Build result: FAILED")
            print(f"Regression report: {regression_log.relative_to(REPO_ROOT)}")
            return 1

        build_result = "REUSED" if before_mtime == after_mtime else "BUILT"
        log_file.write(f"\nBuild result: {build_result}\n")
        print(f"Build result: {build_result}")

        seeds = range(args.seed_start, args.seed_start + args.seed_count)
        results: list[dict[str, object]] = []
        with ThreadPoolExecutor(max_workers=args.jobs) as executor:
            futures = {
                executor.submit(
                    run_seed, core, target, test, seed, args.cycles
                ): seed
                for seed in seeds
            }
            for future in as_completed(futures):
                result = future.result()
                results.append(result)
                print(f"Seed {result['seed']}: {result['result']}")
                log_file.write(f"Seed {result['seed']}: {result['result']}")
                if result["report"]:
                    log_file.write(f" ({result['report']})")
                log_file.write("\n")
                if result["result"] == "FAIL":
                    log_file.write(result["output"])

        results.sort(key=lambda result: int(result["seed"]))
        passed = sum(result["result"] == "PASS" for result in results)
        failed = len(results) - passed
        overall = "PASS" if failed == 0 else "FAIL"
        log_file.write(
            f"\nPassed: {passed}\nFailed: {failed}\nRESULT: {overall}\n"
        )

    machine_results = {
        "core": core,
        "target": target,
        "test": test,
        "seed_start": args.seed_start,
        "seed_count": args.seed_count,
        "jobs": args.jobs,
        "cycles": args.cycles,
        "build_result": build_result,
        "passed": passed,
        "failed": failed,
        "result": overall,
        "runs": [
            {key: value for key, value in result.items() if key != "output"}
            for result in results
        ],
    }
    results_file.write_text(json.dumps(machine_results, indent=2) + "\n")
    print(f"Passed: {passed}  Failed: {failed}  Result: {overall}")
    print(f"Regression report: {regression_log.relative_to(REPO_ROOT)}")
    print(f"Machine results: {results_file.relative_to(REPO_ROOT)}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
