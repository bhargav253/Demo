#!/usr/bin/env python3
"""Remove only Axon-owned disposable build products."""

from __future__ import annotations

import shutil
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
BUILD_ROOT = (REPO_ROOT / "build").resolve()


def main() -> int:
    if BUILD_ROOT.parent != REPO_ROOT.resolve() or BUILD_ROOT.name != "build":
        raise SystemExit(f"refusing unsafe clean target: {BUILD_ROOT}")
    if BUILD_ROOT.exists():
        shutil.rmtree(BUILD_ROOT)
        print(f"Removed disposable build directory: {BUILD_ROOT}")
    else:
        print(f"Build directory is already clean: {BUILD_ROOT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
