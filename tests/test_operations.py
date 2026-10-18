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

        # 2. Conflito D3D9 vs D3D11: D3D11 tem precedência no catálogo genérico (D3D12 > D3D11 > D3D9)
        pe_mixed = {
            'arch': 'x64',
            'year': 2015,
            'imports': ['d3d9.dll', 'd3d11.dll']
        }
        plan_mixed = operations.plan_operations(pe_mixed)
        self.assertIn('op.graphics.d3d11.dxmt', plan_mixed['selected_operations'])
        self.assertNotIn('op.graphics.d3d9.mtld3d', plan_mixed['selected_operations'])
        skipped = [s['operation'] for s in plan_mixed['skipped_conflicts']]
        self.assertIn('op.graphics.d3d9.mtld3d', skipped)

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

        # Configuração validada da receita para cópias novas: WindowedMode=4 e FPSLimit=0
        ini_content = (game / 'scripts/NFSUnderground2.WidescreenFix.ini').read_text()
        self.assertIn('WindowedMode = 4', ini_content)
        self.assertIn('FPSLimit = 0', ini_content)

        # Depois: satisfeito
        self.assertTrue(components.is_satisfied('nfsu2-widescreen-fix', game))

        # Preserva INI existente do usuário se já estiver presente
        (game / 'scripts/NFSUnderground2.WidescreenFix.ini').write_text('WindowedMode = 2\nCustomKey = 99\n')
        # Reexecutar provision_component não deve sobrescrever o INI modificado
        res2 = components.provision_component('nfsu2-widescreen-fix', game, backup_root=data)
        self.assertEqual(res2['status'], 'already_satisfied')
        self.assertIn('CustomKey = 99', (game / 'scripts/NFSUnderground2.WidescreenFix.ini').read_text())

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

    def test_r1_mandatory_component_failure_propagates_and_aborts_profile(self):
        """R1: Falha em componente obrigatório deve propagar exceção e não gerar GameProfile.json."""
        game = self.root / 'game-r1'
        game.mkdir()
        # Cria um EXE dummy com assinatura e cabeçalho PE válidos
        exe = game / 'speed2.exe'
        # Cabeçalho MZ + PE mínimo
        exe_bytes = bytearray(512)
        exe_bytes[:2] = b'MZ'
        exe_bytes[0x3C:0x40] = (64).to_bytes(4, 'little')
        exe_bytes[64:68] = b'PE\0\0'
        # timestamp, opt header
        exe_bytes[68:72] = (0x014c).to_bytes(2, 'little') + (1).to_bytes(2, 'little')
        exe.write_bytes(exe_bytes)

        prefix = self.root / 'prefix-r1'
        resources = self.root / 'resources-r1'
        data = self.root / 'data-r1'

        # Modifica temporariamente o identify ou profile para simular
        plan = {
            'schema': 1,
            'selected_operations': ['op.plugin.nfsu2_widescreen']
        }
        # Simula indisponibilidade de componente obrigatório
        orig_provision = components.provision_component
        try:
            def mock_fail(cid, target, **kwargs):
                raise ValueError('simulated mandatory component unavailable')
            components.provision_component = mock_fail
            operations._components.provision_component = mock_fail

            with self.assertRaises(ValueError) as ctx:
                operations.execute_operations(plan, game, prefix, resources, data)
            self.assertIn('simulated mandatory component unavailable', str(ctx.exception))
            self.assertFalse((data / 'Registros/GameProfile.json').exists())
        finally:
            components.provision_component = orig_provision
            operations._components.provision_component = orig_provision

    def test_r2_symlink_escape_rejected_before_write(self):
        """R2: Link de destino para pasta externa deve ser rejeitado antes de qualquer escrita."""
        game = self.root / 'game-r2'
        game.mkdir()
        outside_dir = self.root / 'outside-r2'
        outside_dir.mkdir()

        # Cria game/scripts como symlink para outside_dir
        (game / 'scripts').symlink_to(outside_dir, target_is_directory=True)

        with self.assertRaises(ValueError) as ctx:
            components.provision_component('nfsu2-widescreen-fix', game, backup_root=self.root / 'backups')
        self.assertIn('Link simbólico detectado', str(ctx.exception))
        # NENHUM arquivo pode ter sido gravado fora da raiz
        self.assertEqual(list(outside_dir.iterdir()), [])

        # Testa também link quebrado
        broken_link = game / 'dinput8.dll'
        broken_link.symlink_to(self.root / 'nonexistent-path')
        with self.assertRaises(ValueError) as ctx:
            components.preflight_target_paths({'mapping': {'dinput8.dll': 'dinput8.dll'}}, game)
        self.assertIn('Link simbólico detectado', str(ctx.exception))

    def test_r3_partial_install_rolled_back_on_write_failure(self):
        """R3: Falha durante escrita sequencial deve restaurar arquivos anteriores e remover novos."""
        game = self.root / 'game-r3'
        game.mkdir()
        original_loader = b'original-loader-content-1234'
        (game / 'dinput8.dll').write_bytes(original_loader)

        backup_root = self.root / 'backups-r3'
        tx = components.ComponentTransaction(game, backup_root)

        # Simula escrita do novo dinput8.dll
        tx.stage_file_write(game / 'dinput8.dll', b'new-dinput8-content')
        self.assertNotEqual((game / 'dinput8.dll').read_bytes(), original_loader)

        # Simula criação da nova ASI
        asi_file = game / 'scripts/test.asi'
        tx.stage_file_write(asi_file, b'new-asi-content')
        self.assertTrue(asi_file.is_file())

        # Duplicata de escrita no mesmo arquivo não pode sobrescrever o backup original
        tx.stage_file_write(game / 'dinput8.dll', b'intermediate-dinput8')

        # Agora ocorre falha (ex: erro simulado de escrita no INI)
        # Executa rollback
        tx.rollback()

        # Arquivo substituído deve ter sido restaurado com o conteúdo original
        self.assertEqual((game / 'dinput8.dll').read_bytes(), original_loader)
        # Arquivo novo criado deve ter sido removido
        self.assertFalse(asi_file.is_file())

    def test_r4_selected_operations_actually_executed_and_recorded(self):
        """R4: Operações selecionadas no plano devem ser concretamente executadas e registradas."""
        game = self.root / 'game-r4'
        game.mkdir()
        prefix = self.root / 'prefix-r4'
        prefix.mkdir()
        resources = self.root / 'resources-r4'
        resources.mkdir()
        data = self.root / 'data-r4'
        data.mkdir()

        plan = {
            'schema': 1,
            'selected_operations': ['op.engine.gta_fps_cap_60', 'op.os.win7_legacy']
        }

        result = operations.execute_operations(plan, game, prefix, resources, data)

        # executed NÃO pode ser vazio
        executed_ops = [item['operation'] for item in result['executed']]
        self.assertIn('op.engine.gta_fps_cap_60', executed_ops)
        self.assertIn('op.os.win7_legacy', executed_ops)

        # mtld3d.conf foi criado e contém present.maxFps = 60
        mtld3d_conf = game / 'mtld3d.conf'
        self.assertTrue(mtld3d_conf.is_file())
        self.assertIn('present.maxFps = 60', mtld3d_conf.read_text())

        # OperationsPlan.json gravado em disco
        plan_json = data / 'Registros/OperationsPlan.json'
        self.assertTrue(plan_json.is_file())
        saved = json.loads(plan_json.read_text())
        self.assertEqual(len(saved['executed']), 2)

    def test_invalid_pe_fails_without_fallback(self):
        """PE inválido deve falhar estritamente sem fallback fictício."""
        game = self.root / 'game-invalid-pe'
        game.mkdir()
        (game / 'speed2.exe').write_bytes(b'not a valid pe file header')
        with unittest.mock.patch.object(profiles, 'identify', return_value={'id': 'nfsu2', 'recipe': 2}):
            with self.assertRaises(ValueError) as ctx:
                profiles.apply(game, 'speed2.exe', self.root / 'prefix', self.root / 'res', self.root / 'data')
            self.assertIn('não é um executável Windows', str(ctx.exception))

    def test_incomplete_zip_payload_fails_before_touching_target(self):
        """ZIP incompleto sem todos os membros mapeados deve falhar antes de tocar o destino."""
        game = self.root / 'game-incomplete-zip'
        game.mkdir()
        fake_archive = self.root / 'incomplete.zip'
        with zipfile.ZipFile(fake_archive, 'w') as z:
            z.writestr('dinput8.dll', b'only dinput8, missing asi')

        fake_comp = {
            'id': 'fake-comp',
            'sha256': '0' * 64,
            'size': fake_archive.stat().st_size,
            'unpacked_limit': 10000,
            'required_files': ['dinput8.dll'],
            'mapping': {
                'dinput8.dll': 'dinput8.dll',
                'scripts/missing.asi': 'scripts/missing.asi'
            }
        }
        orig_load = components.load_manifest
        orig_download = components.ensure_download
        try:
            components.load_manifest = lambda: {'fake-comp': fake_comp}
            components.ensure_download = lambda c, cd=None: fake_archive
            with self.assertRaises(ValueError) as ctx:
                components.provision_component('fake-comp', game)
            self.assertIn('membros ausentes no pacote ZIP', str(ctx.exception))
            # Nada deve ter sido gravado no destino
            self.assertFalse((game / 'dinput8.dll').exists())
            self.assertFalse((game / 'scripts').exists())
        finally:
            components.load_manifest = orig_load
            components.ensure_download = orig_download

    def test_created_file_in_transaction_never_gains_backup_on_subsequent_write(self):
        """Arquivo criado em uma transação e reescrito depois não deve ganhar backup nem ser restaurado no rollback."""
        game = self.root / 'game-no-backup-for-created'
        game.mkdir()
        backup_root = self.root / 'backups-created'

        tx = components.ComponentTransaction(game, backup_root)
        new_file = (game / 'config.ini').resolve()

        # 1ª escrita: cria o arquivo
        tx.stage_file_write(new_file, b'version = 1')
        self.assertIn(new_file, tx.created_files)
        self.assertNotIn(new_file, tx.backups)

        # 2ª escrita no mesmo arquivo na mesma transação
        tx.stage_file_write(new_file, b'version = 2')
        # Não pode ter sido adicionado aos backups!
        self.assertNotIn(new_file, tx.backups)
        self.assertEqual(len(tx.backups), 0)

        # No rollback, deve ser apagado e NÃO restaurado
        tx.rollback()
        self.assertFalse(new_file.exists())

    def test_runtime_compatibility_enforced_when_resources_provided(self):
        """Operações com runtime_compat devem verificar presença dos componentes no runtime fornecido."""
        game = self.root / 'game-compat'
        game.mkdir()
        res_with_wine = self.root / 'resources-with-wine'
        (res_with_wine / 'wine').mkdir(parents=True)
        data = self.root / 'data-compat'
        data.mkdir()

        plan = {
            'schema': 1,
            'selected_operations': ['op.cpu.x87sidecar']
        }
        # Falha porque x87sidecar não existe em resources (mas wine existe)
        with self.assertRaises(RuntimeError) as ctx:
            operations.execute_operations(plan, game, None, res_with_wine, data)
        self.assertIn('x87sidecar ausente', str(ctx.exception))


if __name__ == '__main__':
    unittest.main()
