import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1] / 'scripts'

def module(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / (name + '.py'))
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded

profiles = module('btp-game-profile')
ops = profiles._operations

class ReleaseIntegration(unittest.TestCase):
    def test_tested_recipe_wins_over_missing_static_imports_and_timestamp(self):
        recipe = profiles.PROFILES['gta_sa.exe']
        plan = ops.plan_operations({'arch': 'i386', 'imports': ['kernel32.dll'], 'year': 0}, recipe=recipe)
        self.assertEqual(plan['selected_operations'], recipe['operations'])

    def test_settings_export_is_consumable_and_cannot_execute_values(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            marker = root / 'must-not-exist'
            record = root / 'profile.json'
            value = "native;$(touch '" + str(marker) + "')"
            record.write_text(json.dumps({'launch_settings': {'renderer': 'd3d9=mtld3d',
                'windows': 'win7', 'x87': True, 'overrides': value, 'game_args': '-memory 1048576'}}))
            exported = profiles.export_launch_settings(record)
            result = subprocess.check_output(['/bin/bash', '-c', exported + '\nprintf "%s\\n" "$OP_RENDERER" "$OP_WINDOWS" "$OP_X87" "$OP_OVERRIDES" "$OP_ARGS"'], text=True)
            self.assertEqual(result.splitlines(), ['d3d9=mtld3d', 'win7', '1', value, '-memory 1048576'])
            self.assertFalse(marker.exists())

    def test_mandatory_failure_propagates_through_profile_without_early_config_write(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); game = root / 'game'; game.mkdir()
            (game / 'gta_sa.exe').write_bytes(b'fixture')
            config = game / 'mtld3d.conf'; config.write_text('present.maxFps = 0\nquality = 8\n')
            pe = SimpleNamespace(is64=False, subsystem=2, timestamp=0, imports=lambda: ['d3d9.dll'])
            with patch.object(profiles, 'identify', return_value={'id': 'gtasa'}), patch.object(profiles._peinfo, 'PE', return_value=pe), patch.object(ops, 'execute_operations', side_effect=RuntimeError('mandatory failure')):
                with self.assertRaisesRegex(RuntimeError, 'mandatory failure'):
                    profiles.apply(game, 'gta_sa.exe', root/'prefix', None, root/'data')
            self.assertEqual(config.read_text(), 'present.maxFps = 0\nquality = 8\n')
            self.assertFalse((root/'data/Registros/GameProfile.json').exists())

    def test_later_plugin_failure_rolls_back_earlier_cap(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); game = root / 'game'; game.mkdir()
            config = game / 'mtld3d.conf'; config.write_text('present.maxFps = 0\nquality = 8\n')
            plan = {'selected_operations': ['op.engine.gta_fps_cap_60', 'op.plugin.nfsu2_widescreen']}
            with patch.object(ops._components, 'provision_component', side_effect=OSError('disk failure')):
                with self.assertRaisesRegex(OSError, 'disk failure'):
                    ops.execute_operations(plan, game, None, None, root/'data')
            self.assertEqual(config.read_text(), 'present.maxFps = 0\nquality = 8\n')
            self.assertFalse((root/'data/Registros/OperationsPlan.json').exists())

    def test_configuration_symlink_cannot_write_outside_copy(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); game = root/'game'; game.mkdir()
            outside = root/'outside'; outside.write_text('unchanged')
            (game/'mtld3d.conf').symlink_to(outside)
            with self.assertRaises(ValueError):
                ops.execute_operations({'selected_operations':['op.engine.gta_fps_cap_60']}, game, None, None, root/'data')
            self.assertEqual(outside.read_text(), 'unchanged')

    def test_wrong_runtime_version_is_rejected_despite_existing_wine_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); (root/'wine').mkdir()
            (root/'Runtime.json').write_text(json.dumps({'components': {'wine': {'version': 'other'}}}))
            with self.assertRaisesRegex(RuntimeError, 'Versão Wine incompatível'):
                ops.check_runtime_compatibility(ops.OPERATIONS['op.os.win7_legacy'], root)

if __name__ == '__main__':
    unittest.main()
