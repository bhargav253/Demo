#!/usr/bin/env python3
"""Build once, run an isolated Verilator coverage campaign, and merge it."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import shlex
import shutil
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


def command_output(command: list[str]) -> str:
    result = subprocess.run(command, check=True, text=True, capture_output=True)
    return (result.stdout or result.stderr).strip()


def build_identity(work_root: Path, simulator: Path) -> tuple[str, dict[str, object]]:
    version = command_output(["verilator", "--version"])
    inputs = [simulator]
    inputs.extend(sorted(work_root.glob("*.eda.yml")))
    inputs.extend(sorted(work_root.glob("*.vc")))
    digest = hashlib.sha256()
    digest.update(version.encode())
    records = []
    for path in inputs:
        file_digest = hashlib.sha256(path.read_bytes()).hexdigest()
        digest.update(path.name.encode())
        digest.update(file_digest.encode())
        records.append({"file": path.name, "sha256": file_digest})
    return digest.hexdigest(), {"verilator": version, "inputs": records}


def run_one(
    simulator: Path,
    work_root: Path,
    campaign_dir: Path,
    test: str,
    seed: int,
    cycles: int,
) -> dict[str, object]:
    safe_test = SAFE_PART.sub("_", test)
    run_dir = campaign_dir / "runs" / safe_test / f"seed-{seed}"
    run_dir.mkdir(parents=True, exist_ok=False)
    coverage_file = run_dir / "coverage.dat"
    report = run_dir / "sim.log"
    command = [
        str(simulator),
        f"+TEST={test}",
        f"+SEED={seed}",
        f"+CYCLES={cycles}",
        f"+AXON_COVERAGE_FILE={coverage_file}",
    ]
    with report.open("w", encoding="utf-8") as log_file:
        log_file.write(f"Test: {test}\nSeed: {seed}\nCycles: {cycles}\n")
        log_file.write(f"Command: {shlex.join(command)}\n\n")
        status = stream_command(command, work_root, log_file)
        result = "PASS" if status == 0 and coverage_file.is_file() else "FAIL"
        if status == 0 and not coverage_file.is_file():
            status = 1
            log_file.write("\nerror: simulator did not produce coverage.dat\n")
        log_file.write(f"\nRESULT: {result}\nExit status: {status}\n")
    return {
        "test": test,
        "seed": seed,
        "cycles": cycles,
        "result": result,
        "exit_status": status,
        "report": str(report.relative_to(REPO_ROOT)),
        "coverage": str(coverage_file.relative_to(REPO_ROOT)) if coverage_file.is_file() else "",
    }


def previous_coverage(path_text: str | None, identity: str) -> Path | None:
    if not path_text:
        return None
    path = Path(path_text).expanduser()
    if not path.is_absolute():
        path = REPO_ROOT / path
    manifest_path = path / "coverage-manifest.json"
    merged_path = path / "merged.dat"
    if not manifest_path.is_file() or not merged_path.is_file():
        fail("MERGE_FROM must contain coverage-manifest.json and merged.dat")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("build_identity") != identity:
        fail("MERGE_FROM was produced by a different coverage build identity")
    return merged_path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core", required=True)
    parser.add_argument("--target", default="coverage")
    parser.add_argument("--tests", default="smoke,directed,random")
    parser.add_argument("--seed-start", type=int, default=1)
    parser.add_argument("--seed-count", type=int, default=1)
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--cycles", type=int, default=200)
    parser.add_argument("--merge-from")
    parser.add_argument("--rebuild", action="store_true")
    args = parser.parse_args()

    core = args.core.strip()
    target = args.target.strip()
    tests = [item.strip() for item in args.tests.split(",") if item.strip()]
    if not FULL_VLNV.fullmatch(core):
        fail("CORE must be a complete axon:<library>:<name>:<version> VLNV")
    if not target.startswith("coverage"):
        fail("TARGET must name a coverage target")
    if not tests:
        fail("TESTS must contain at least one test")
    if args.seed_start < 0 or args.seed_count < 1 or args.jobs < 1 or args.cycles < 1:
        fail("seed start must be non-negative; count, jobs, and cycles must be positive")
    if shutil.which("verilator_coverage") is None:
        fail("verilator_coverage is required")
    available = target_names(core_info(core))
    if target not in available:
        fail(f"core {core} has no target '{target}'")

    safe_core = SAFE_PART.sub("_", core)
    safe_target = SAFE_PART.sub("_", target)
    work_root = REPO_ROOT / "build" / safe_core / safe_target
    timestamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%S.%fZ")
    campaign_id = f"{timestamp}-{os.getpid()}-{uuid.uuid4().hex[:8]}"
    campaign_dir = REPO_ROOT / "artifacts" / safe_core / "coverage" / campaign_id
    campaign_dir.mkdir(parents=True, exist_ok=False)
    campaign_log = campaign_dir / "coverage.log"

    build_command = [str(FUSESOC), "run"]
    if args.rebuild:
        build_command.append("--clean")
    build_command += ["--build", "--target", target, "--work-root", str(work_root), core]
    print(f"Axon coverage: {core} tests={','.join(tests)}")
    print(f"Build directory: {work_root.relative_to(REPO_ROOT)}")
    print(f"Campaign directory: {campaign_dir.relative_to(REPO_ROOT)}")
    work_root.parent.mkdir(parents=True, exist_ok=True)
    lock_path = work_root.parent / f".{target}.lock"
    with campaign_log.open("w", encoding="utf-8") as log_file:
        log_file.write(f"Core: {core}\nTarget: {target}\n")
        log_file.write(f"Build command: {shlex.join(build_command)}\n\n")
        with lock_path.open("w", encoding="utf-8") as lock_file:
            fcntl.flock(lock_file, fcntl.LOCK_EX)
            before = find_simulator(work_root)
            before_mtime = before.stat().st_mtime_ns if before else None
            build_status = stream_command(build_command, REPO_ROOT, log_file)
            simulator = find_simulator(work_root)
            after_mtime = simulator.stat().st_mtime_ns if simulator else None
            fcntl.flock(lock_file, fcntl.LOCK_UN)
        if build_status or simulator is None:
            log_file.write("\nBuild result: FAILED\nRESULT: FAIL\n")
            print(f"Result: FAIL\nReport: {campaign_log.relative_to(REPO_ROOT)}")
            return 1
        build_result = "REUSED" if before_mtime == after_mtime else "BUILT"
        identity, identity_details = build_identity(work_root, simulator)
        prior = previous_coverage(args.merge_from, identity)
        log_file.write(f"\nBuild result: {build_result}\nBuild identity: {identity}\n")

        jobs: list[tuple[str, int]] = []
        for test in tests:
            if test == "random":
                jobs.extend((test, seed) for seed in range(args.seed_start, args.seed_start + args.seed_count))
            else:
                jobs.append((test, args.seed_start))
        results = []
        with ThreadPoolExecutor(max_workers=args.jobs) as executor:
            futures = {
                executor.submit(run_one, simulator, work_root, campaign_dir, test, seed, args.cycles): (test, seed)
                for test, seed in jobs
            }
            for future in as_completed(futures):
                result = future.result()
                results.append(result)
                print(f"{result['test']} seed {result['seed']}: {result['result']}")
                log_file.write(f"{result['test']} seed {result['seed']}: {result['result']} ({result['report']})\n")
        results.sort(key=lambda item: (str(item["test"]), int(item["seed"])))
        failed = sum(item["result"] != "PASS" for item in results)
        coverage_inputs = [REPO_ROOT / str(item["coverage"]) for item in results if item["result"] == "PASS"]
        if prior:
            coverage_inputs.insert(0, prior)

        merged = campaign_dir / "merged.dat"
        annotate_dir = campaign_dir / "annotated"
        info_file = campaign_dir / "coverage.info"
        summary_file = campaign_dir / "summary.txt"
        summary_json = campaign_dir / "summary.json"
        merge_status = 0
        if failed == 0 and coverage_inputs:
            merge_command = ["verilator_coverage", "--write", str(merged), *map(str, coverage_inputs)]
            log_file.write(f"Command: {shlex.join(merge_command)}\n")
            merge_status = stream_command(merge_command, work_root, log_file)
            if merge_status == 0:
                annotate_command = ["verilator_coverage", "--annotate", str(annotate_dir), str(merged)]
                log_file.write(f"Command: {shlex.join(annotate_command)}\n")
                summary = subprocess.run(annotate_command, cwd=work_root, text=True, capture_output=True)
                summary_text = summary.stdout + summary.stderr
                print(summary_text, end="")
                log_file.write(summary_text)
                summary_file.write_text(summary_text, encoding="utf-8")
                merge_status = summary.returncode
            if merge_status == 0:
                info_command = ["verilator_coverage", "--write-info", str(info_file), str(merged)]
                log_file.write(f"Command: {shlex.join(info_command)}\n")
                merge_status = stream_command(info_command, work_root, log_file)
            if merge_status == 0:
                report_command = [
                    sys.executable,
                    str(REPO_ROOT / "scripts" / "coverage" / "report.py"),
                    str(merged),
                    "--text", str(summary_file),
                    "--json", str(summary_json),
                ]
                log_file.write(f"Command: {shlex.join(report_command)}\n")
                merge_status = stream_command(report_command, REPO_ROOT, log_file)
        else:
            merge_status = 1
        overall = "PASS" if failed == 0 and merge_status == 0 else "FAIL"
        log_file.write(f"\nRuns: {len(results)}\nFailed: {failed}\nRESULT: {overall}\n")

    manifest = {
        "core": core, "target": target, "tests": tests,
        "seed_start": args.seed_start, "seed_count": args.seed_count,
        "jobs": args.jobs, "cycles": args.cycles,
        "build_result": build_result, "build_identity": identity,
        "build_identity_details": identity_details,
        "merge_from": str(prior.parent.relative_to(REPO_ROOT)) if prior and REPO_ROOT in prior.parents else (str(prior.parent) if prior else None),
        "result": overall, "runs": results,
    }
    (campaign_dir / "coverage-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Runs: {len(results)}  Failed: {failed}  Result: {overall}")
    print(f"Coverage report: {campaign_dir.relative_to(REPO_ROOT)}")
    return 0 if overall == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
