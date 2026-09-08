"""Bounded subprocess execution and retained single-target run evidence."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import resource
import selectors
import signal
import subprocess
import sys
import time


def digest(path: Path) -> str:
    with path.open('rb') as handle:
        value = hashlib.sha256()
        for chunk in iter(lambda: handle.read(1024*1024), b''):
            value.update(chunk)
        return value.hexdigest()


def provenance(root: Path) -> dict:
    def query(command):
        try:
            p = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=15)
            return (p.stdout or p.stderr).strip()
        except (OSError, subprocess.TimeoutExpired) as exc:
            return str(exc)
    status = query(['git', 'status', '--porcelain'])
    versions = {}
    for tool, args in [('verilator', ['--version']), ('yosys', ['-V']), ('sby', ['--version']), ('boolector', ['--version'])]:
        local = root / '.tools/oss-cad-suite/bin' / tool
        versions[tool] = query([str(local) if local.exists() else tool, *args])
    versions['python'] = query(['python3', '--version'])
    versions['fusesoc'] = query([str(root / 'tools/bin/fusesoc'), '--version'])
    versions['edalize'] = query([str(root / '.venv/bin/python'), '-c', 'import importlib.metadata; print(importlib.metadata.version("edalize"))'])
    return {'revision': query(['git', 'rev-parse', 'HEAD']), 'dirty': bool(status),
            'git_status': status, 'diff_sha256': hashlib.sha256(query(['git', 'diff', 'HEAD', '--binary']).encode()).hexdigest(),
            'tool_versions': versions}


def save(path: Path, data: dict):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(data, indent=2) + '\n')
    temporary.replace(path)


def execute(command, cwd, log_file, timeout=600, max_log_bytes=2*1024*1024,
            max_file_bytes=1024*1024*1024, echo=False):
    """Kill the process group on timeout, interruption or excess output.

    File size limits apply in the child, including FST traces. No shell is used.
    """
    child_command = [sys.executable, str(Path(__file__).resolve()),
                     '--child', str(max_file_bytes), *command]
    process = subprocess.Popen(child_command, cwd=cwd, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, start_new_session=True)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + timeout
    size = 0
    reason = None
    previous = {}
    def interrupted(signum, frame):
        raise KeyboardInterrupt
    for sig in (signal.SIGINT, signal.SIGTERM):
        # Legacy campaign builders may invoke this helper from a worker thread.
        try:
            previous[sig] = signal.signal(sig, interrupted)
        except ValueError:
            pass
    try:
        while selector.get_map():
            if time.monotonic() >= deadline:
                reason = 'TIMEOUT'
                break
            for key, _ in selector.select(min(.1, max(0, deadline-time.monotonic()))):
                data = os.read(key.fd, 65536)
                if not data:
                    selector.unregister(key.fileobj)
                    continue
                remaining = max_log_bytes-size
                chunk = data[:max(0, remaining)].decode(errors='replace')
                log_file.write(chunk)
                if echo:
                    print(chunk, end='', flush=True)
                log_file.flush()
                size += len(data)
                if size > max_log_bytes:
                    reason = 'OUTPUT_LIMIT'
                    break
            if reason:
                break
        if not reason:
            process.wait(timeout=max(.01, deadline-time.monotonic()))
    except subprocess.TimeoutExpired:
        reason = 'TIMEOUT'
    except KeyboardInterrupt:
        reason = 'INTERRUPTED'
    finally:
        if reason or process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        process.wait()
        selector.close()
        process.stdout.close()
        for sig, handler in previous.items():
            signal.signal(sig, handler)
    code = {'TIMEOUT':124, 'INTERRUPTED':130, 'OUTPUT_LIMIT':125}.get(reason, process.returncode)
    if reason:
        log_file.write(f'\nExecution stopped: {reason}\n')
    return code


if __name__ == '__main__':
    # Apply limits in a fresh interpreter, never via preexec_fn from worker threads.
    if len(sys.argv) < 4 or sys.argv[1] != '--child':
        raise SystemExit('internal child launcher requires --child LIMIT COMMAND')
    limit = int(sys.argv[2])
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    resource.setrlimit(resource.RLIMIT_FSIZE, (limit, limit))
    os.execvpe(sys.argv[3], sys.argv[3:], os.environ)
