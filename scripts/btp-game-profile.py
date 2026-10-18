#!/usr/bin/env python3
"""Regras explícitas para as edições testadas. Só altera a cópia preparada."""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import shlex

HERE = Path(__file__).resolve().parent
PROFILES = json.loads((HERE / 'game-profiles.json').read_text())['profiles']

import importlib.util
_op_spec = importlib.util.spec_from_file_location('btp_operations', HERE / 'btp-operations.py')
_operations = importlib.util.module_from_spec(_op_spec)
_op_spec.loader.exec_module(_operations)


_pe_spec = importlib.util.spec_from_file_location('btp_peinfo', HERE / 'btp-peinfo.py')
_peinfo = importlib.util.module_from_spec(_pe_spec)
_pe_spec.loader.exec_module(_peinfo)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def identify(executable):
    profile = PROFILES.get(executable.name.lower())
    if profile and digest(executable) not in profile['tested_executable_sha256']:
        raise ValueError('Esta edição ainda não foi validada pelo BTP. O executável foi preservado; não será substituído. Use uma edição compatível ou aguarde um perfil para ela.')
    return profile


def set_values(path, values, backup):
    old = path.read_text() if path.exists() else ''
    lines = old.splitlines()
    for key, value in values.items():
        positions = [i for i, line in enumerate(lines) if line.split('=', 1)[0].strip() == key]
        if positions:
            for i in positions:
                lines[i] = key + ' = ' + str(value)
        else:
            lines.append(key + ' = ' + str(value))
    new = '\n'.join(lines) + '\n'
    if old != new:
        if path.exists():
            backup.mkdir(parents=True, exist_ok=True)
            backup_file = backup / path.name
            if not backup_file.exists():
                shutil.copy2(path, backup_file)
        path.write_text(new)


def ensure_nfs_data_drive(game, prefix):
    # The tested NFS edition enumerates D: during RealCore initialization.
    # A fresh C:/Z: prefix faulted at 0x006f7429; a private D: data alias
    # passed startup and a user-driven session. Never replace an existing drive.
    alias = prefix / 'dosdevices/d:'
    if alias.exists() or alias.is_symlink():
        return False
    game.relative_to(prefix / 'drive_c')
    alias.symlink_to(os.path.relpath(game, alias.parent), target_is_directory=True)
    return True


def apply(game, exe, prefix, resources, data):
    executable = game / exe
    profile = identify(executable)
    if not profile:
        return
    backup = data / 'Backups/Profiles' / datetime.now().strftime('%Y%m%d-%H%M%S-%f')

    # Extrai fatos PE reais do executável do jogo; falha estritamente se não for PE válido
    raw = executable.read_bytes()
    pe = _peinfo.PE(raw)
    pe_info = {
        'arch': 'x64' if pe.is64 else 'i386',
        'subsystem': pe.subsystem,
        'timestamp': pe.timestamp,
        'imports': pe.imports(),
        'year': datetime.utcfromtimestamp(pe.timestamp).year if pe.timestamp > 0 else 0
    }

    # Executa o plano de operações e provisiona plugins ausentes; falhas obrigatórias propagam
    plan = _operations.plan_operations(pe_info, recipe=profile, target_game=game)
    exec_res = _operations.execute_operations(plan, game, prefix, resources, data)
    launch_settings = exec_res.get('launch_settings', {})

    if profile['id'] == 'nfsu2':
        try:
            relative = game.relative_to(prefix / 'drive_c')
        except ValueError:
            relative = Path('Games') / game.name
        windows = 'C:\\' + str(relative).replace('/', '\\') + '\\'
        added_data_drive = ensure_nfs_data_drive(game, prefix)
        alias = prefix / 'dosdevices/d:'
        managed_data_drive = added_data_drive or (alias.is_symlink() and alias.resolve() == game.resolve())
        env = dict(os.environ, WINEPREFIX=str(prefix), WINEARCH='wow64', WINELOADERNOEXEC='1',
                   WINEDEBUG='-all', WINESERVER=str(resources / 'wine/bin/wineserver'))
        log = data / 'Registros/nfs-registry.log'
        log.parent.mkdir(parents=True, exist_ok=True)
        with log.open('ab') as output:
            if managed_data_drive:
                subprocess.run([str(resources / 'GameRuntime.app/Contents/MacOS/wine'), 'reg', 'add',
                                'HKCU\\Software\\Wine\\Drives', '/v', 'd:', '/t', 'REG_SZ',
                                '/d', 'floppy', '/f'], env=env, stdout=output, stderr=output,
                               check=True, timeout=40)
            for company in ('EA Games', 'Electronic Arts\\EA Games'):
                key = 'HKLM\\Software\\' + company + '\\Need for Speed Underground 2'
                for value in ('Install Dir', 'InstallDir', 'Path', 'CD Drive'):
                    subprocess.run([str(resources / 'GameRuntime.app/Contents/MacOS/wine'), 'reg', 'add', key,
                                    '/v', value, '/t', 'REG_SZ', '/d', windows, '/f', '/reg:32'],
                                   env=env, stdout=output, stderr=output, check=True, timeout=40)
                for value, kind, content in (('Language', 'REG_SZ', 'English US'), ('Locale', 'REG_SZ', 'en_us'), ('VERSION', 'REG_DWORD', '1')):
                    subprocess.run([str(resources / 'GameRuntime.app/Contents/MacOS/wine'), 'reg', 'add', key,
                                    '/v', value, '/t', kind, '/d', content, '/f', '/reg:32'],
                                   env=env, stdout=output, stderr=output, check=True, timeout=40)
            subprocess.run([str(resources / 'wine/bin/wineserver'), '-w'], env=env,
                           stdout=output, stderr=output, check=True, timeout=40)
    record = dict(profile, executable_sha256=digest(executable), source_executable_preserved=True, launch_settings=launch_settings)
    (data / 'Registros/GameProfile.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')


def export_launch_settings(record):
    settings = json.loads(Path(record).read_text()).get('launch_settings', {})
    names = {'renderer': 'OP_RENDERER', 'windows': 'OP_WINDOWS',
             'overrides': 'OP_OVERRIDES', 'game_args': 'OP_ARGS'}
    lines = [name + '=' + shlex.quote(str(settings.get(key, ''))) for key, name in names.items()]
    lines.append('OP_X87=' + ('1' if settings.get('x87') else '0'))
    return '\n'.join(lines)


def finalize_operations(data, app):
    path = data / 'Registros/OperationsPlan.json'
    if not path.is_file():
        return
    record = json.loads(path.read_text())
    launcher = (app / 'Contents/Resources/launch-game.sh').read_text()
    runtime = json.loads((app / 'Contents/Resources/Runtime.json').read_text())
    for item in record.get('executed', []):
        if item['action'] == 'launch_setting_declared':
            item['action'] = 'consumed_by_launcher'
        elif item['action'] == 'pending_stage':
            if not runtime.get('per_game_adjustments'):
                raise RuntimeError('Ajuste privado do renderizador não foi aplicado.')
            item['action'] = 'applied_private_stage'
    record['generated_app'] = str(app)
    record['launcher_sha256'] = hashlib.sha256(launcher.encode()).hexdigest()
    path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')


def patch_gta_runtime(resources):
    # Receita mtld3d usada pelo GTA local. Nunca modificar o motor compartilhado.
    path = resources / 'wine/lib/wine/d3d9/mtld3d/i386-windows/d3d9.dll'
    raw = path.read_bytes()
    before, after = bytes.fromhex('b8ffff9e00'), bytes.fromhex('b8ffff9e01')
    original = 'd9c04787c9e7d1bddd25b340d363074f4d3071e5bac3735267bacde5ed7412a7'
    if hashlib.sha256(raw).hexdigest() != original:
        raise ValueError('Renderizador não corresponde à versão testada da receita GTA.')
    if before not in raw:
        raise ValueError('Versão do renderizador diferente da receita GTA; operação interrompida.')
    path.write_bytes(raw.replace(before, after))
    record = resources / 'Runtime.json'
    if record.is_file():
        state = json.loads(record.read_text())
        key = 'wine/lib/wine/d3d9/mtld3d/i386-windows/d3d9.dll'
        state['files'][key] = digest(path)
        state['per_game_adjustments'] = [{'profile': 'gtasa', 'component': key,
                                        'original_sha256': original, 'sha256': digest(path)}]
        record.write_text(json.dumps(state, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', type=Path)
    parser.add_argument('--settings', type=Path)
    parser.add_argument('--patch-gta-runtime', type=Path)
    parser.add_argument('--export-launch-settings', type=Path)
    parser.add_argument('--finalize-app', type=Path)
    for name in ('game', 'prefix', 'resources', 'data'):
        parser.add_argument('--' + name, type=Path)
    parser.add_argument('--exe')
    args = parser.parse_args()
    if args.export_launch_settings:
        print(export_launch_settings(args.export_launch_settings))
    elif args.finalize_app:
        finalize_operations(args.data, args.finalize_app)
    elif args.settings:
        profile = identify(args.settings)
        if profile:
            print('|'.join(({'nfsu2': 'NFSU2', 'gtasa': 'GTASA'}[profile['id']], profile['renderer'], profile['windows'])))
        else:
            print('||')
    elif args.check:
        identify(args.check)
    elif args.patch_gta_runtime:
        patch_gta_runtime(args.patch_gta_runtime)
    else:
        apply(args.game, args.exe, args.prefix, args.resources, args.data)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        raise SystemExit('BTP: ' + str(error))
