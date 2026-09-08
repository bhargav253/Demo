"""Failure-path tests: process cleanup, output limits and interrupts."""
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from evidence import execute


class ExecutionTests(unittest.TestCase):
    def run_program(self, program, **kwargs):
        with tempfile.TemporaryDirectory() as directory:
            with (Path(directory)/'run.log').open('w+') as log:
                code = execute([sys.executable, '-c', program], Path(directory), log, **kwargs)
                log.seek(0)
                return code, log.read()

    def test_timeout_with_silent_descendant(self):
        start = time.monotonic()
        code, log = self.run_program('import subprocess,sys; subprocess.Popen([sys.executable,"-c","import time; time.sleep(60)"])', timeout=.2)
        self.assertEqual(code, 124)
        self.assertLess(time.monotonic()-start, 3)
        self.assertIn('TIMEOUT', log)

    def test_unterminated_output_is_bounded(self):
        code, log = self.run_program('import os; os.write(1,b"x"*1000000)', max_log_bytes=4096)
        self.assertEqual(code, 125)
        self.assertLess(len(log), 4200)

    def test_file_size_limit(self):
        code, _ = self.run_program('open("wave.fst","wb").write(b"x"*100000)', max_file_bytes=4096)
        self.assertNotEqual(code, 0)

    def test_exit_status(self):
        code, _ = self.run_program('raise SystemExit(7)')
        self.assertEqual(code, 7)

    def test_sigterm_cleanup(self):
        module_dir = str(Path(__file__).resolve().parents[1])
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            script = ('import sys; sys.path.insert(0, '+repr(module_dir)+'); '
                      'from evidence import execute; from pathlib import Path; '
                      'root=Path('+repr(directory)+'); '
                      'code=execute([sys.executable,"-c","import time; print(123,flush=True); time.sleep(60)"],root,open(root/"log","w")); '
                      '(root/"result").write_text(str(code))')
            process = subprocess.Popen([sys.executable, '-c', script])
            try:
                deadline = time.monotonic()+5
                while not (path/'log').exists() or not (path/'log').stat().st_size:
                    if time.monotonic() > deadline:
                        self.fail('child failed to start')
                    time.sleep(.02)
                process.send_signal(signal.SIGTERM)
                process.wait(timeout=3)
                self.assertEqual((path/'result').read_text(), '130')
            finally:
                if process.poll() is None:
                    process.kill()
                process.wait()

if __name__ == '__main__':
    unittest.main()
