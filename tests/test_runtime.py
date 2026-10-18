import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1] / 'scripts'

def module(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / (name + '.py'))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

runtime, profiles = module('btp-runtime'), module('btp-game-profile')

class Components(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
    def tearDown(self):
        self.tmp.cleanup()
    def archive(self, members):
        path = self.root / 'test.tar'
        with tarfile.open(path, 'w') as tar:
            for name, target in members:
                item = tarfile.TarInfo(name)
                if target is not None:
                    item.type, item.linkname = tarfile.SYMTYPE, target
                    tar.addfile(item)
                else:
                    item.size = 2
                    tar.addfile(item, io.BytesIO(b'OK'))
        return path
    def test_malicious_paths_and_links_write_nothing(self):
        for members in ([('../escape',None)], [('a','/tmp/out')], [('a','.'),('b','a/../escape')],
                        [('a','b'),('b','a')], [('a','inside'),('a/file',None)], [('a',None),('a',None)]):
            with self.subTest(members=members):
                destination = self.root / 'out'
                with self.assertRaises(ValueError):
                    runtime.extract(self.archive(members), destination, 100)
                self.assertFalse(destination.exists())
    def test_legitimate_relative_link(self):
        out = self.root / 'out'
        runtime.extract(self.archive([('tree/data',None),('tree/bin/a','../data')]),out,100)
        self.assertEqual((out/'tree/bin/a').read_bytes(),b'OK')
    def test_checksum_failure_preserves_existing_cache(self):
        cache = self.root/'cache'; cache.mkdir()
        component = dict(url='https://github.com/test/test/releases/download/v1/test.tar.xz', sha256='a'*64,size=3,version='test')
        old = cache/('a'*64+'.tar.xz'); old.write_bytes(b'old')
        def download(argv, **kw):
            Path(argv[argv.index('--output')+1]).write_bytes(b'bad')
        with patch.object(runtime,'CACHE',cache),patch.object(runtime.subprocess,'run',side_effect=download):
            with self.assertRaises(ValueError):runtime.download(component)
        self.assertEqual(old.read_bytes(),b'old')
        self.assertEqual(len(list(cache.iterdir())),1)
    def test_incomplete_existing_prefix_preserved(self):
        prefix=self.root/'prefix'; prefix.mkdir(); (prefix/'marker').write_text('keep')
        with self.assertRaises(RuntimeError):runtime.initialize_prefix(self.root,prefix)
        self.assertEqual((prefix/'marker').read_text(),'keep')
    def test_unknown_game_edition_preserved(self):
        exe=self.root/'gta_sa.exe'; exe.write_bytes(b'unknown edition')
        with self.assertRaises(ValueError):profiles.identify(exe)
        self.assertEqual(exe.read_bytes(),b'unknown edition')
    def test_cap_preserves_quality_and_backup(self):
        dummy_pe = bytearray(512)
        dummy_pe[:2] = b'MZ'
        dummy_pe[0x3C:0x40] = (64).to_bytes(4, 'little')
        dummy_pe[64:68] = b'PE\0\0'
        dummy_pe[68:72] = (0x014c).to_bytes(2, 'little') + (1).to_bytes(2, 'little')
        exe_bytes = bytes(dummy_pe)
        game=self.root/'game';game.mkdir();(game/'gta_sa.exe').write_bytes(exe_bytes)
        data=self.root/'data';(data/'Registros').mkdir(parents=True)
        config=game/'mtld3d.conf'; old='quality = 8\nshader.asyncCompile = true\npresent.maxFps = 0\n'
        config.write_text(old)
        with patch.object(profiles,'identify',return_value={'id':'gtasa'}):
            profiles.apply(game,'gta_sa.exe',self.root/'prefix',self.root/'resources',data)
        self.assertIn('quality = 8',config.read_text())
        self.assertIn('shader.asyncCompile = true',config.read_text())
        self.assertIn('present.maxFps = 60',config.read_text())
        backups=list((data/'Backups/Profiles').rglob(config.name))
        self.assertEqual(len(backups),1)
        self.assertEqual(backups[0].read_text(),old)
        self.assertEqual((game/'gta_sa.exe').read_bytes(),exe_bytes)
    def test_unrecognized_renderer_unmodified(self):
        dll=self.root/'wine/lib/wine/d3d9/mtld3d/i386-windows/d3d9.dll'
        dll.parent.mkdir(parents=True); dll.write_bytes(bytes.fromhex('b8ffff9e00'))
        with self.assertRaises(ValueError):profiles.patch_gta_runtime(self.root)
        self.assertEqual(dll.read_bytes(),bytes.fromhex('b8ffff9e00'))
    def test_nfs_data_drive_does_not_replace_existing_mapping(self):
        prefix=self.root/'prefix'; game=prefix/'drive_c/Games/NFSU2'
        game.mkdir(parents=True); (prefix/'dosdevices').mkdir()
        drive=prefix/'dosdevices/d:'; drive.symlink_to('../unmounted-volume')
        self.assertFalse(profiles.ensure_nfs_data_drive(game,prefix))
        self.assertEqual(str(drive.readlink()),'../unmounted-volume')
    def test_nfs_data_drive_stays_in_private_prefix(self):
        prefix=self.root/'prefix'; game=prefix/'drive_c/Games/NFSU2'
        game.mkdir(parents=True); (prefix/'dosdevices').mkdir()
        self.assertTrue(profiles.ensure_nfs_data_drive(game,prefix))
        drive=prefix/'dosdevices/d:'
        self.assertEqual(drive.resolve(),game.resolve())
        self.assertFalse(drive.readlink().is_absolute())

if __name__=='__main__':unittest.main()
