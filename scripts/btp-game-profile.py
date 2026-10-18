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

HERE = Path(__file__).resolve().parent
PROFILES = json.loads((HERE / 'game-profiles.json').read_text())['profiles']


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
            shutil.copy2(path, backup / path.name)
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
    if profile['id'] == 'gtasa':
        set_values(executable.parent / 'mtld3d.conf', {'present.maxFps': 60, 'shader.asyncCompile': 'false'}, backup)
    if profile['id'] == 'nfsu2':
        relative = game.relative_to(prefix / 'drive_c')
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
    record = dict(profile, executable_sha256=digest(executable), source_executable_preserved=True)
    (data / 'Registros/GameProfile.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')


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
    for name in ('game', 'prefix', 'resources', 'data'):
        parser.add_argument('--' + name, type=Path)
    parser.add_argument('--exe')
    args = parser.parse_args()
    if args.settings:
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
