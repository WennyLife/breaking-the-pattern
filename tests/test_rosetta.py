import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('swiftc'), 'Native macOS test')
class RosettaSetup(unittest.TestCase):
    def test_native_gate_does_not_resume_after_cancellation_or_failed_install(self):
        with tempfile.TemporaryDirectory(prefix='btp-rosetta-test-') as temporary:
            binary = Path(temporary) / 'gate-tests'
            subprocess.run(['swiftc', str(ROOT/'src/BTPRosettaSetup.swift'),
                            str(ROOT/'tests/RosettaSetupTests.swift'), '-o', str(binary)],
                           check=True, capture_output=True, text=True)
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
            self.assertIn('cancellation, launch error, missing helper passed', result.stdout)


if __name__ == '__main__':
    unittest.main()
