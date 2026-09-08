# SPDX-License-Identifier: Apache-2.0
"""Bounded, cancellable local process execution; no shell or worker preexec_fn."""
import os
from pathlib import Path
import resource
import selectors
import signal
import subprocess
import sys
import time


def run(command, cwd, log, timeout, max_log, max_file, cancel):
    start = time.monotonic()
    if cancel.is_set():
        return {'exit_status':130,'status':'CANCELLED','seconds':0}
    child = [sys.executable, str(Path(__file__).resolve()), '--child', str(max_file), *map(str,command)]
    process = subprocess.Popen(child,cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,start_new_session=True)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout,selectors.EVENT_READ)
    status = None
    size = 0
    try:
        with Path(log).open('wb') as output:
            while selector.get_map():
                if cancel.is_set(): status = 'CANCELLED'; break
                if time.monotonic()-start >= timeout: status = 'TIMEOUT'; break
                for key,_ in selector.select(.05):
                    chunk = os.read(key.fd,65536)
                    if not chunk:
                        selector.unregister(key.fileobj);continue
                    output.write(chunk[:max(0,max_log-size)])
                    output.flush()
                    size += len(chunk)
                    if size > max_log: status = 'OUTPUT_LIMIT';break
                if status: break
            while not status and process.poll() is None:
                if cancel.is_set(): status = 'CANCELLED'
                elif time.monotonic()-start >= timeout: status = 'TIMEOUT'
                else: time.sleep(.02)
            if status:
                output.write(f'\n{status}\n'.encode())
    finally:
        if status or process.poll() is None:
            try: os.killpg(process.pid,signal.SIGKILL)
            except ProcessLookupError: pass
        process.wait()
        process.stdout.close()
        selector.close()
    code = {'CANCELLED':130,'TIMEOUT':124,'OUTPUT_LIMIT':125}.get(status, process.returncode)
    return {'exit_status':code,'status':status or ('PASS' if code==0 else 'FAIL'),
            'seconds':round(time.monotonic()-start,3)}


if __name__ == '__main__':
    if len(sys.argv)<4 or sys.argv[1]!='--child': raise SystemExit(2)
    limit=int(sys.argv[2])
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    resource.setrlimit(resource.RLIMIT_FSIZE,(limit,limit))
    os.execvpe(sys.argv[3],sys.argv[3:],os.environ)
