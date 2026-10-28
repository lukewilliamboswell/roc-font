"""Regression tests for concurrent package-cache ownership, without Roc."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

WORKER = '''
import sys
from pathlib import Path
import flight
with flight.cache_lease(Path(sys.argv[1]), sys.argv[2] == "prune"):
    Path(sys.argv[1]).mkdir(parents=True, exist_ok=True)
    print("ready", flush=True)
    sys.stdin.readline()
'''

@unittest.skipIf(sys.platform == 'win32', 'flock unavailable; cache is preserved')
class ConcurrentCache(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='roc-font-cache-test-')
        self.addCleanup(temporary.cleanup)
        self.entry = Path(temporary.name) / 'package'

    def worker(self, prune=True):
        env = {**os.environ, 'PYTHONPATH': str(Path(__file__).resolve().parent)}
        process = subprocess.Popen([sys.executable, '-c', WORKER, str(self.entry), 'prune' if prune else 'keep'],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, env=env)
        def cleanup():
            if process.poll() is None:
                process.kill()
            process.communicate()
        self.addCleanup(cleanup)
        self.assertEqual(process.stdout.readline(), 'ready\n')
        return process

    def finish(self, process):
        _, error = process.communicate('\n', timeout=10)
        self.assertEqual(process.returncode, 0, error)

    def test_cleanup_waits_for_the_last_process(self):
        first = self.worker()
        second = self.worker()
        self.finish(first)
        self.assertTrue(self.entry.is_dir())
        self.finish(second)
        self.assertFalse(self.entry.exists())

    def test_preexisting_cache_survives(self):
        self.entry.mkdir()
        first = self.worker()
        second = self.worker()
        self.finish(first)
        self.finish(second)
        self.assertTrue(self.entry.is_dir())

    def test_keep_request_survives_a_later_pruning_process(self):
        first = self.worker(prune=False)
        second = self.worker()
        self.finish(first)
        self.finish(second)
        self.assertTrue(self.entry.is_dir())

    def test_crash_releases_the_lease_and_preserves_existing_data(self):
        first = self.worker()
        first.kill()
        first.communicate(timeout=10)
        second = self.worker()
        self.finish(second)
        self.assertTrue(self.entry.is_dir())

if __name__ == '__main__':
    unittest.main()
