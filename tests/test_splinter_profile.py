import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location('profile', Path(__file__).resolve().parents[1] / 'scripts/btp-splinter-profile.py')
profile = importlib.util.module_from_spec(spec)
spec.loader.exec_module(profile)


class ProfileTests(unittest.TestCase):
    def fixture(self, root, unsafe=None):
        prefix = root / 'prefix'
        game = prefix / 'drive_c/Games/Conviction/src/system'
        game.mkdir(parents=True)
        (game / 'Conviction_game.exe').write_bytes(b'fixture: not an executable')
        (game / 'ConvictionUserPC.ini').write_text('StartupFullscreen=True\nWindowedViewportX=1024\nWindowedViewportY=768\nTextureQuality=3\n')
        (game / 'version.dll').write_bytes(b'previous loader')
        archive = root / 'fix.zip'
        with zipfile.ZipFile(archive, 'w') as z:
            z.writestr('src/system/version.dll', b'test loader')
            z.writestr('src/system/scripts/SplinterCellConviction.FusionFix.asi', b'test ASI')
            z.writestr('src/system/scripts/SplinterCellConviction.FusionFix.ini', 'WindowedMode = 0 // comment\nFPSLimit = 0\nUnlockDLC = 1\n')
            if unsafe:z.writestr(unsafe, 'must not escape')
        return game, prefix, root / 'data', archive

    def test_unknown_executable_preserved(self):
        with tempfile.TemporaryDirectory() as tmp:
            game, prefix, data, archive = self.fixture(Path(tmp))
            before = (game / 'version.dll').read_bytes()
            with self.assertRaises(ValueError):profile.prepare(game, prefix, data, archive)
            self.assertEqual((game / 'version.dll').read_bytes(), before)
            self.assertFalse(data.exists())

    def test_zip_escape_rejected_before_write(self):
        with tempfile.TemporaryDirectory() as tmp:
            game, prefix, data, archive = self.fixture(Path(tmp), 'src/system/../../escape.txt')
            with patch.object(profile, 'EXE_SHA256', profile.sha256(game/'Conviction_game.exe')), patch.object(profile, 'FIX_SHA256', profile.sha256(archive)):
                with self.assertRaises(ValueError):profile.prepare(game, prefix, data, archive)
            self.assertEqual((game/'version.dll').read_bytes(), b'previous loader')
            self.assertFalse(data.exists())

    def test_config_preserves_quality_and_executable(self):
        with tempfile.TemporaryDirectory() as tmp:
            game, prefix, data, archive = self.fixture(Path(tmp))
            original = (game/'Conviction_game.exe').read_bytes()
            with patch.object(profile, 'EXE_SHA256', profile.sha256(game/'Conviction_game.exe')), patch.object(profile, 'FIX_SHA256', profile.sha256(archive)):
                profile.prepare(game, prefix, data, archive)
            self.assertEqual((game/'Conviction_game.exe').read_bytes(), original)
            self.assertIn('TextureQuality=3', (game/'ConvictionUserPC.ini').read_text())
            self.assertEqual(len(list((data/'Backups').glob('*/drive_c/Games/Conviction/src/system/version.dll'))), 1)
            self.assertTrue((data/'Registros/conviction-profile.json').is_file())

    def test_partial_write_restores_previous_loader(self):
        with tempfile.TemporaryDirectory() as tmp:
            game, prefix, data, archive = self.fixture(Path(tmp))
            real_write = Path.write_bytes
            failed = False
            def fail_once(path, content):
                nonlocal failed
                if path.suffix == '.asi' and not failed:
                    failed = True
                    raise OSError('simulated disk failure')
                return real_write(path, content)
            with patch.object(profile, 'EXE_SHA256', profile.sha256(game/'Conviction_game.exe')), patch.object(profile, 'FIX_SHA256', profile.sha256(archive)), patch.object(Path, 'write_bytes', fail_once):
                with self.assertRaises(OSError):profile.prepare(game, prefix, data, archive)
            self.assertEqual((game/'version.dll').read_bytes(), b'previous loader')
            self.assertIn('StartupFullscreen=True', (game/'ConvictionUserPC.ini').read_text())


if __name__ == '__main__':unittest.main()
