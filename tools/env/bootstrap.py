#!/usr/bin/env python3
"""Create the repository-local Axon hardware-tool environment."""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import venv
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
VENV_DIR = REPO_ROOT / ".venv"
LOCK_FILE = REPO_ROOT / "requirements" / "tools.lock"
LOCAL_PROJECTS = (
    REPO_ROOT / "scripts" / "edalize",
    REPO_ROOT / "scripts" / "fusesoc",
)
MARKER = VENV_DIR / ".axon-bootstrap.json"
MIN_PYTHON = (3, 10)


def fingerprint() -> str:
    digest = hashlib.sha256()
    inputs = [LOCK_FILE, Path(__file__), *(p / "pyproject.toml" for p in LOCAL_PROJECTS)]
    for path in inputs:
        digest.update(str(path.relative_to(REPO_ROOT)).encode())
        digest.update(path.read_bytes())
    digest.update(f"{sys.version_info.major}.{sys.version_info.minor}".encode())
    return digest.hexdigest()


def run(command: list[str]) -> None:
    print("+", " ".join(command), flush=True)
    subprocess.run(command, cwd=REPO_ROOT, check=True)


def environment_is_current(expected: str) -> bool:
    python = VENV_DIR / "bin" / "python"
    if not python.is_file() or not MARKER.is_file():
        return False
    try:
        state = json.loads(MARKER.read_text())
    except (OSError, json.JSONDecodeError):
        return False
    if state.get("fingerprint") != expected:
        return False
    check = (
        "import edalize.edatool, fusesoc.main; "
        "from pathlib import Path; "
        f"root=Path({str(REPO_ROOT)!r}).resolve(); "
        "assert root in Path(edalize.edatool.__file__).resolve().parents; "
        "assert root in Path(fusesoc.main.__file__).resolve().parents"
    )
    return subprocess.run([str(python), "-c", check], cwd=REPO_ROOT).returncode == 0


def main() -> int:
    if sys.version_info < MIN_PYTHON:
        print(
            f"error: Python {MIN_PYTHON[0]}.{MIN_PYTHON[1]} or newer is required; "
            f"found {sys.version.split()[0]}",
            file=sys.stderr,
        )
        return 2

    expected = fingerprint()
    if environment_is_current(expected):
        print(f"Axon tool environment is current: {VENV_DIR}")
        return 0

    if not (VENV_DIR / "bin" / "python").is_file():
        print(f"Creating Python environment: {VENV_DIR}")
        venv.EnvBuilder(with_pip=True).create(VENV_DIR)

    python = str(VENV_DIR / "bin" / "python")
    run([python, "-m", "pip", "install", "--disable-pip-version-check", "-r", str(LOCK_FILE)])
    run([
        python,
        "-m",
        "pip",
        "install",
        "--disable-pip-version-check",
        "--no-deps",
        "--no-build-isolation",
        "--editable",
        str(LOCAL_PROJECTS[0]),
        "--editable",
        str(LOCAL_PROJECTS[1]),
    ])
    run([python, "-m", "pip", "check"])

    MARKER.write_text(json.dumps({
        "fingerprint": expected,
        "python": sys.version.split()[0],
        "local_projects": [str(path.relative_to(REPO_ROOT)) for path in LOCAL_PROJECTS],
    }, indent=2) + "\n")

    if not environment_is_current(expected):
        print("error: environment installed but local package validation failed", file=sys.stderr)
        return 1

    print(f"Axon tool environment ready: {VENV_DIR}")
    print("Run `make doctor` to inspect the complete tool environment.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
