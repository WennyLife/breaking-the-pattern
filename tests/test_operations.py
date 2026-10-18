import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest
import zipfile

HERE = Path(__file__).resolve().parent
SCRIPTS = HERE.parent / 'scripts'


def load_module(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f'{name}.py')
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


components = load_module('btp-components')
operations = load_module('btp-operations')
profiles = load_module('btp-game-profile')


class OperationsAndComponentsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_component_manifest_validity(self):
        manifest = components.load_manifest()
        self.assertIn('nfsu2-widescreen-fix', manifest)
        self.assertIn('gtasa-widescreen-fix', manifest)
        self.assertIn('gtasa-silentpatch', manifest)
        self.assertIn('splintercell-fusionfix', manifest)

        for cid, item in manifest.items():
            self.assertEqual(item['id'], cid)
            self.assertTrue(item['url'].startswith('https://github.com/'))
            self.assertIn('/releases/', item['url'])
            self.assertEqual(len(item['sha256']), 64)
            self.assertGreater(item['size'], 0)
            self.assertGreater(item.get('unpacked_limit', 0), item['size'])
            self.assertIn(item['classification'], ('necessario', 'opcional'))
            self.assertIsInstance(item['required_files'], list)
            self.assertGreater(len(item['required_files']), 0)
            self.assertIsInstance(item['mapping'], dict)

    def test_operations_catalog_validity(self):
        ops = operations.OPERATIONS
        self.assertIn('op.graphics.d3d9.mtld3d', ops)
        self.assertIn('op.graphics.d3d11.dxmt', ops)
        self.assertIn('op.cpu.x87sidecar', ops)
        self.assertIn('op.os.win7_legacy', ops)
        self.assertIn('op.plugin.nfsu2_widescreen', ops)
        self.assertIn('op.plugin.gtasa_widescreen', ops)
        self.assertIn('op.plugin.gtasa_silentpatch', ops)

        for op_id, op in ops.items():
            self.assertEqual(op['id'], op_id)
            self.assertIn('category', op)
            self.assertIn('when', op)
            self.assertIn('evidence', op)
            self.assertIsInstance(op.get('conflicts_with', []), list)

    def test_composition_and_conflict_resolution(self):
        # 1. PE D3D9 + i386 + ano 2004
        pe_info = {
            'arch': 'i386',
            'year': 2004,
            'imports': ['d3d9.dll', 'kernel32.dll', 'user32.dll']
        }
        plan = operations.plan_operations(pe_info)
        selected = plan['selected_operations']

        # Operações genéricas compatíveis devem ser selecionadas
        self.assertIn('op.graphics.d3d9.mtld3d', selected)
        self.assertIn('op.cpu.x87sidecar', selected)
        self.assertIn('op.os.win7_legacy', selected)

        # Operações restritas a receitas específicas NÃO devem ser transferidas
        self.assertNotIn('op.storage.nfs_data_drive', selected)
        self.assertNotIn('op.engine.gta_fps_cap_60', selected)
        self.assertNotIn('op.engine.gta_memory_arg', selected)
        self.assertNotIn('op.wine.gta_media_overrides', selected)
        self.assertNotIn('op.patch.gta_mtld3d_renderer', selected)
        self.assertNotIn('op.plugin.nfsu2_widescreen', selected)

        # 2. Conflito D3D9 vs D3D11
        pe_mixed = {
            'arch': 'x64',
            'year': 2015,
            'imports': ['d3d9.dll', 'd3d11.dll']
        }
        plan_mixed = operations.plan_operations(pe_mixed)
        # Primeira no catálogo (d3d9) entra, e d3d11 que está em conflicts_with é pulada
        self.assertIn('op.graphics.d3d9.mtld3d', plan_mixed['selected_operations'])
        self.assertNotIn('op.graphics.d3d11.dxmt', plan_mixed['selected_operations'])
        skipped = [s['operation'] for s in plan_mixed['skipped_conflicts']]
        self.assertIn('op.graphics.d3d11.dxmt', skipped)

    def test_nfsu2_clean_folder_provisioning(self):
        game = self.root / 'NFSU2'
        game.mkdir()
        exe = game / 'SPEED2.EXE'
        exe.write_bytes(b'dummy-speed2')
        data = self.root / 'data'
        (data / 'Registros').mkdir(parents=True)
        prefix = self.root / 'prefix'
        (prefix / 'drive_c/Games').mkdir(parents=True)
        (prefix / 'dosdevices').mkdir(parents=True)
        resources = self.root / 'resources'
        resources.mkdir()

        # Antes: não satisfeito
        self.assertFalse(components.is_satisfied('nfsu2-widescreen-fix', game))

        # Provisiona em cópia isolada
        res = components.provision_component('nfsu2-widescreen-fix', game, backup_root=data)
        self.assertEqual(res['status'], 'provisioned')
        self.assertTrue((game / 'dinput8.dll').is_file())
        self.assertTrue((game / 'scripts/NFSUnderground2.WidescreenFix.asi').is_file())
        self.assertTrue((game / 'scripts/NFSUnderground2.WidescreenFix.ini').is_file())
        self.assertTrue((game / 'scripts/NFSUnderground2.WidescreenFix.dat').is_file())

        # Depois: satisfeito
        self.assertTrue(components.is_satisfied('nfsu2-widescreen-fix', game))

    def test_gtasa_clean_folder_preserves_vorbis_and_provisions(self):
        game = self.root / 'GTASA'
        game.mkdir()
        exe = game / 'gta_sa.exe'
        exe.write_bytes(b'dummy-gta')
        original_vorbis = b'original-game-vorbisfile-dll-content'
        (game / 'vorbisFile.dll').write_bytes(original_vorbis)
        data = self.root / 'data'
        (data / 'Registros').mkdir(parents=True)

        self.assertFalse(components.is_satisfied('gtasa-widescreen-fix', game))
        self.assertFalse(components.is_satisfied('gtasa-silentpatch', game))

        # Provisiona widescreen fix: vorbisFile original vira vorbisHooked e ASI loader entra
        res_ws = components.provision_component('gtasa-widescreen-fix', game, backup_root=data)
        self.assertEqual(res_ws['status'], 'provisioned')
        self.assertTrue((game / 'vorbisHooked.dll').is_file())
        self.assertEqual((game / 'vorbisHooked.dll').read_bytes(), original_vorbis)
        self.assertGreater((game / 'vorbisFile.dll').stat().st_size, 1_000_000)
        self.assertTrue((game / 'scripts/GTASA.WidescreenFix.asi').is_file())
        self.assertTrue(components.is_satisfied('gtasa-widescreen-fix', game))

        # Provisiona SilentPatch
        res_sp = components.provision_component('gtasa-silentpatch', game, backup_root=data)
        self.assertEqual(res_sp['status'], 'provisioned')
        self.assertTrue((game / 'scripts/SilentPatchSA.asi').is_file())
        self.assertTrue(components.is_satisfied('gtasa-silentpatch', game))

        # Backups foram gerados
        backups = list((data / 'Backups/Components').rglob('*'))
        self.assertGreater(len(backups), 0)

    def test_malicious_archive_traversal_rejected(self):
        fake_component = {
            'id': 'malicious-test',
            'sha256': '0' * 64,
            'size': 100,
            'unpacked_limit': 1000,
            'mapping': {'evil.dll': 'evil.dll'}
        }
        archive_path = self.root / 'malicious.zip'
        with zipfile.ZipFile(archive_path, 'w') as z:
            z.writestr('../evil.dll', b'malicious payload')

        with zipfile.ZipFile(archive_path) as z:
            with self.assertRaises(ValueError):
                components.validate_zip_payload(z, fake_component)


if __name__ == '__main__':
    unittest.main()
