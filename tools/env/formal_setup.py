#!/usr/bin/env python3
"""Install the pinned free OSS CAD Suite into this checkout."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
LOCK_FILE = REPO_ROOT / "requirements" / "formal-tools.json"
TOOLS_ROOT = REPO_ROOT / ".tools"
INSTALL_DIR = TOOLS_ROOT / "oss-cad-suite"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    if sys.platform != "linux" or os.uname().machine != "x86_64":
        print("error: the pinned formal bundle supports Linux x86-64", file=sys.stderr)
        return 2
    lock = json.loads(LOCK_FILE.read_text(encoding="utf-8"))
    marker = INSTALL_DIR / ".axon-formal-tools.json"
    if marker.is_file() and all((INSTALL_DIR / "bin" / tool).is_file() for tool in ("yosys", "sby", "boolector")):
        state = json.loads(marker.read_text(encoding="utf-8"))
        if state.get("sha256") == lock["sha256"]:
            print(f"Axon formal tools are current: {INSTALL_DIR}")
            return 0

    TOOLS_ROOT.mkdir(parents=True, exist_ok=True)
    archive = TOOLS_ROOT / Path(lock["url"]).name
    if not archive.is_file() or sha256(archive) != lock["sha256"]:
        print(
            f"Downloading {lock['suite']} {lock['release']} "
            f"({lock['archive_bytes'] / 1024 / 1024:.1f} MiB)...",
            flush=True,
        )
        temporary = archive.with_suffix(archive.suffix + ".tmp")
        urllib.request.urlretrieve(lock["url"], temporary)
        if sha256(temporary) != lock["sha256"]:
            temporary.unlink(missing_ok=True)
            print("error: formal tool archive checksum mismatch", file=sys.stderr)
            return 1
        temporary.replace(archive)

    with tempfile.TemporaryDirectory(prefix="formal-install-", dir=TOOLS_ROOT) as temp:
        temp_path = Path(temp)
        subprocess.run(["tar", "-xzf", str(archive), "-C", str(temp_path)], check=True)
        extracted = temp_path / "oss-cad-suite"
        if not (extracted / "bin" / "yosys").is_file():
            print("error: unexpected OSS CAD Suite archive layout", file=sys.stderr)
            return 1
        if INSTALL_DIR.exists():
            shutil.rmtree(INSTALL_DIR)
        extracted.replace(INSTALL_DIR)

    marker.write_text(json.dumps({
        "release": lock["release"],
        "sha256": lock["sha256"],
        "source": lock["url"],
    }, indent=2) + "\n", encoding="utf-8")
    environment = os.environ.copy()
    environment["PATH"] = f"{INSTALL_DIR / 'bin'}:{environment['PATH']}"
    for command in (["yosys", "-V"], ["sby", "--version"], ["boolector", "--version"]):
        subprocess.run(command, env=environment, check=True)
    print(f"Axon formal tools installed: {INSTALL_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
