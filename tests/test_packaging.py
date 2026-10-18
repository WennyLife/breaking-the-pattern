import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

SOURCE = Path(__file__).resolve().parents[1] / 'scripts/break-game.sh'
results = []


def put(path, content, executable=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    if executable:
        path.chmod(0o755)


def snapshot(root):
    entries = {}
    for p in sorted(root.rglob('*')):
        rel = str(p.relative_to(root))
        if p.is_symlink():
            entries[rel] = ['link', os.readlink(p)]
        elif p.is_file():
            entries[rel] = ['file', hashlib.sha256(p.read_bytes()).hexdigest()]
        else:
            entries[rel] = ['dir']
    return entries


with tempfile.TemporaryDirectory(prefix='btp-script-tests-') as temporary:
    root = Path(temporary)
    for symlink in (False, True):
        case = root / ('collision-link' if symlink else 'collision-direct')
        apps = case / 'Applications'
        target = apps / 'Need for Speed Underground 2.app'
        actual = case / 'Actual.app' if symlink else target
        resources = actual / 'Contents/Resources'
        (resources / 'GameRuntime.app').mkdir(parents=True)
        if symlink:
            apps.mkdir()
            target.symlink_to(actual)
        put(actual / 'preserve.txt', 'working app')
        game = case / 'Game'
        put(game / 'test.exe', 'dummy PE not executed')
        env = dict(os.environ, BTP_APPS_DIR=str(apps), BTP_DONOR_RESOURCES=str(resources))
        before = snapshot(case)
        result = subprocess.run(['/bin/bash', str(SOURCE), '--title', target.stem,
                                 '--game-dir', str(game), '--exe', 'test.exe'],
                                env=env, text=True, capture_output=True)
        assert result.returncode != 0 and 'se sobrepõem' in result.stderr, result
        assert snapshot(case) == before, 'Collision changed files'
        results.append({'case': case.name, 'status': 'PASS', 'no_mutations': True})

    for mode in ('wine-fails', 'wineserver-fails', 'signature-fails', 'install-fails', 'success'):
        case = root / mode
        apps = case / 'Applications'
        target = apps / 'Nested Test.app'
        put(target / 'preserve.txt', 'working app')
        resources = case / 'Donor.app/Contents/Resources'
        for relative in ('PrefixSeed/drive_c', 'GameRuntime.app', 'Underground 2 FPS.app'):
            (resources / relative).mkdir(parents=True)
        put(resources / 'RuntimeBootstrap', 'dummy bootstrap', True)
        put(resources / 'x87sidecar', 'dummy sidecar', True)
        put(resources / 'GameRuntime.app/Contents/MacOS/wine',
            '#!/bin/bash\necho "simulated Wine configuration"\n'
            '[[ "$BTP_TEST_MODE" != wine-fails ]]\n', True)
        put(resources / 'wine/bin/wineserver',
            '#!/bin/bash\necho "simulated wineserver"\n'
            '[[ "$BTP_TEST_MODE" != wineserver-fails ]]\n', True)
        game = case / 'Game'
        put(game / 'src/system/game.exe', 'dummy executable; never run')
        icon = case / 'icon.icns'
        put(icon, 'dummy icon')
        scripts = case / 'project/scripts'
        # The copied script redirects only its data root into the temporary test
        # sandbox. HOME and the real user applications remain unchanged.
        source = SOURCE.read_text()
        original_data = 'DATA_DIR="$HOME/Library/Application Support/$TITLE"'
        assert source.count(original_data) == 1
        put(scripts / 'break-game.sh', source.replace(original_data, 'DATA_DIR="$BTP_TEST_DATA/$TITLE"'))
        put(scripts / 'btp-peinfo.py', 'import json\nprint(json.dumps({"arch":"i386","year":2010,"renderer":"d3d9=mtld3d","compatibility":{"windows":"win7","x87":True}}))\n')
        shutil.copy2(SOURCE.with_name('btp-rules.py'), scripts / 'btp-rules.py')
        put(scripts / 'BTPGameLauncher', '#!/bin/bash\nexit 0\n', True)
        stubs = case / 'stubs'
        put(stubs / 'codesign', '#!/bin/bash\n'
            '[[ -f "$BTP_TEST_TARGET/preserve.txt" ]] || exit 99\n'
            'if [[ "$1" == --verify && "$BTP_TEST_MODE" == signature-fails ]]; then exit 42; fi\n'
            'exit 0\n', True)
        put(stubs / 'mv', '#!/bin/bash\n'
            'if [[ "$BTP_TEST_MODE" == install-fails && "$1" == */.btp-build.*/Game.app ]]; then exit 72; fi\n'
            'exec /bin/mv "$@"\n', True)
        env = dict(os.environ, BTP_APPS_DIR=str(apps), BTP_DONOR_RESOURCES=str(resources),
                   BTP_TEST_DATA=str(case / 'data'), BTP_TEST_MODE=mode,
                   BTP_TEST_TARGET=str(target), PATH=str(stubs) + ':' + os.environ['PATH'])
        result = subprocess.run(['/bin/bash', str(scripts / 'break-game.sh'), '--title', 'Nested Test',
                                 '--game-dir', str(game), '--exe', 'src/system/game.exe', '--icon', str(icon)],
                                env=env, text=True, capture_output=True)
        data = case / 'data/Nested Test'
        configured = data / 'prefix-metal/drive_c/Games/NestedTest/src/system/mtld3d.conf'
        assert not list(apps.glob('.btp-build.*')), 'Temporary build leaked'
        if mode == 'success':
            assert result.returncode == 0, result.stderr
            assert not (target / 'preserve.txt').exists()
            backups = list((data / 'Backups/Apps').glob('*/Nested Test.app/preserve.txt'))
            assert len(backups) == 1 and backups[0].read_text() == 'working app'
            assert (target / 'Contents/Resources/launch-game.sh').exists()
            assert configured.exists()
            assert not (configured.parents[2] / 'mtld3d.conf').exists()
        else:
            assert result.returncode != 0, result.stdout
            assert (target / 'preserve.txt').read_text() == 'working app'
            if mode in ('wine-fails', 'wineserver-fails'):
                assert 'Falha' in result.stderr
                logs = list((data / 'Registros').glob('config-windows-*'))
                assert len(logs) == 1 and 'simulated Wine' in logs[0].read_text()
                assert not configured.exists()
            else:
                assert configured.exists()
        results.append({'case': mode, 'status': 'PASS', 'exit_code': result.returncode,
                        'previous_app_preserved': mode != 'success',
                        'backup_retained': mode == 'success'})

report = {'source': str(SOURCE), 'source_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
          'scope': 'Isolated dummy fixtures; no real game executed, built, or published; signing simulated.',
          'results': results}
print(json.dumps(report, indent=2))
