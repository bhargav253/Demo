#!/usr/bin/env python3
"""Report the Axon development environment without modifying it."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
VENV_PYTHON = REPO_ROOT / ".venv" / "bin" / "python"
FORMAL_BIN = REPO_ROOT / ".tools" / "oss-cad-suite" / "bin"
REQUIRED_COMMANDS = {
    "git": ["--version"],
    "make": ["--version"],
    "gcc": ["--version"],
    "g++": ["--version"],
    "verilator": ["--version"],
    "verilator_coverage": ["--version"],
}
OPTIONAL_COMMANDS = {
    "yosys": ["-V"],
    "sby": ["--version"],
}


def find_command(name: str) -> str | None:
    repository_tool = FORMAL_BIN / name
    if repository_tool.is_file() and repository_tool.stat().st_mode & 0o111:
        return str(repository_tool)
    return shutil.which(name)


def first_line(command: list[str]) -> str:
    result = subprocess.run(command, capture_output=True, text=True, timeout=10)
    output = (result.stdout or result.stderr).strip().splitlines()
    return output[0] if output else f"exit {result.returncode}"


def main() -> int:
    failures: list[str] = []
    print(f"Repository : {REPO_ROOT}")
    print(f"Host Python: {sys.version.split()[0]} ({sys.executable})")
    if sys.version_info < (3, 10):
        failures.append("host Python 3.10 or newer is required")

    print("\nRequired host tools:")
    for name, args in REQUIRED_COMMANDS.items():
        executable = find_command(name)
        if executable is None:
            print(f"  MISSING  {name}")
            failures.append(f"required command not found: {name}")
        else:
            print(f"  OK       {name}: {first_line([executable, *args])} [{executable}]")

    print("\nOptional/planned host tools:")
    for name, args in OPTIONAL_COMMANDS.items():
        executable = find_command(name)
        if executable is None:
            print(
                f"  NOT SET  {name} (run `python3 tools/env/formal_setup.py` "
                "for Stage 1D)"
            )
        else:
            print(f"  OK       {name}: {first_line([executable, *args])} [{executable}]")

    print("\nRepository Python environment:")
    if not VENV_PYTHON.is_file():
        print("  MISSING  .venv; run `python3 tools/env/bootstrap.py`")
        failures.append("repository Python environment is not bootstrapped")
    else:
        probe = (
            "from importlib.metadata import version; "
            "import edalize.edatool, fusesoc.main; "
            "print(version('axon-fusesoc')); print(fusesoc.main.__file__); "
            "print(version('axon-edalize')); print(edalize.edatool.__file__)"
        )
        result = subprocess.run(
            [str(VENV_PYTHON), "-c", probe],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
        )
        if result.returncode:
            print("  BROKEN   local FuseSoC/Edalize imports; run `python3 tools/env/bootstrap.py`")
            failures.append("repository Python packages do not import")
        else:
            lines = result.stdout.strip().splitlines()
            print(f"  OK       axon-fusesoc {lines[0]}: {lines[1]}")
            print(f"  OK       axon-edalize {lines[2]}: {lines[3]}")
            for module_path in (Path(lines[1]), Path(lines[3])):
                if REPO_ROOT not in module_path.resolve().parents:
                    failures.append(f"package is not loaded from this repository: {module_path}")

    print("\nRepository configuration:")
    for relative in ("fusesoc.conf", "requirements/tools.lock", "tools/bin/fusesoc"):
        path = REPO_ROOT / relative
        state = "OK" if path.is_file() else "MISSING"
        print(f"  {state:<8} {relative}")
        if not path.is_file():
            failures.append(f"required repository file missing: {relative}")

    if failures:
        print("\nEnvironment is not ready:")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print("\nEnvironment is ready for Axon development commands.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
