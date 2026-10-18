import importlib.util
import itertools
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1] / 'scripts'
spec = importlib.util.spec_from_file_location('rules', SCRIPTS / 'btp-rules.py')
rules = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rules)


class KnowledgeBase(unittest.TestCase):
    def test_preserves_previous_preparation_decisions(self):
        # Compare against build7, including mixed imports and missing COFF date.
        dlls = ['d3d9.dll', 'd3d11.dll', 'd3d12.dll', 'dxgi.dll', 'd3d8.dll']
        for arch, year, flags in itertools.product(['i386', 'x64', 'arm64'],
                                                   [0, 1995, 2011, 2012, 2026],
                                                   itertools.product([False, True], repeat=len(dlls))):
            imports = [dll for dll, present in zip(dlls, flags) if present]
            expected = ('dxgi=gptk' if arch == 'x64' and 'd3d12.dll' in imports else
                        'dxgi=dxmt' if set(imports).intersection(['d3d11.dll', 'dxgi.dll']) else
                        'd3d9=mtld3d' if 'd3d9.dll' in imports else '')
            plan = rules.evaluate(arch, year, imports)
            self.assertEqual(plan['renderer'], expected)
            self.assertEqual(plan['windows'], 'win7' if 0 < year < 2012 else '')
            self.assertEqual(plan['x87'], arch == 'i386')
            self.assertFalse(plan['gameplay_validated'])

    def test_generic_rules_never_transfer_game_specific_fixes(self):
        for arch in ('i386', 'x64'):
            plan = rules.evaluate(arch, 2004, ['d3d9.dll'])
            self.assertEqual(set(plan) - {'schema', 'catalog_revision', 'catalog_sha256',
                                         'applied_rules', 'gameplay_validated'},
                             {'renderer', 'windows', 'x87'})
            self.assertNotIn('fps_cap', plan)
            self.assertNotIn('data_drive', plan)
            self.assertNotIn('patch', plan)

    def test_static_dll_strings_can_select_backend_without_import(self):
        self.assertEqual(rules.evaluate('i386', 0, [], [b'D3D9.DLL'])['renderer'], 'd3d9=mtld3d')
        self.assertEqual(rules.evaluate('x64', 0, [], ['d3d10_1.dll'])['renderer'], 'dxgi=dxmt')

    def test_unknown_actions_or_predicates_rejected_without_execution(self):
        source = json.loads(rules.CATALOG.read_text())
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'rules.json'
            for where, key, value in [('set', 'command', 'touch /tmp/unwanted'),
                                       ('when', 'filename', 'gta_sa.exe'),
                                       ('set', 'renderer', '$(touch /tmp/unwanted)'),
                                       ('set', 'x87', 1)]:
                data = json.loads(json.dumps(source))
                data['rules'][0][where][key] = value
                path.write_text(json.dumps(data))
                with patch.object(rules, 'CATALOG', path), self.assertRaises(ValueError):
                    rules.evaluate('x64', 0, ['d3d12.dll'])

    def test_decision_record_keeps_overrides_separate_and_not_validated(self):
        plan = rules.evaluate('i386', 2004, ['d3d9.dll'])
        analysis = {'arch': 'i386', 'year': 2004, 'compatibility': plan,
                    'executable_sha256': 'a' * 64}
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / 'CompatibilityPlan.json'
            subprocess.run(['python3', '-I', '-B', str(SCRIPTS / 'btp-rules.py'),
                            '--record', str(target), '--analysis', json.dumps(analysis),
                            '--renderer', '', '--windows', 'win7', '--profile', 'GTASA'],
                           check=True)
            saved = json.loads(target.read_text())
            self.assertEqual(saved['effective']['renderer'], 'wined3d')
            self.assertEqual(saved['analysis']['compatibility']['renderer'], 'd3d9=mtld3d')
            self.assertEqual(saved['effective']['game_profile'], 'GTASA')
            self.assertFalse(saved['analysis']['compatibility']['gameplay_validated'])
            self.assertFalse(target.with_suffix('.tmp').exists())


if __name__ == '__main__':
    unittest.main()
