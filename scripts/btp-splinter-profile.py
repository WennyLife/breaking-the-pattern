#!/usr/bin/env python3
"""Prepara o perfil Conviction validado localmente, sem substituir o executável."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import tempfile
import urllib.request
import zipfile

EXE_SHA256 = '6d5f7fb8b71956d2bf2840dd9bbea6b9cdd21e8fe8d19dd4cad9d876ab535e0c'
FIX_SHA256 = 'ebc392c5f5e1ade0d160dfcf0325c53cc528b8683e1c3c7df115f12e91015e3c'
FIX_URL = 'https://github.com/ThirteenAG/WidescreenFixesPack/releases/download/scc/SplinterCellConviction.FusionFix.zip'


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def payload_plan(archive, game):
    """Valida todos os destinos antes de extrair qualquer componente."""
    plan = []
    total = 0
    for item in archive.infolist():
        rel = PurePosixPath(item.filename)
        if rel.is_absolute() or '..' in rel.parts or '\\' in item.filename:
            raise ValueError('Caminho inválido no pacote de compatibilidade.')
        if stat.S_ISLNK(item.external_attr >> 16):
            raise ValueError('Links não são aceitos no pacote de compatibilidade.')
        if item.is_dir():
            continue
        if rel.parts[:2] != ('src', 'system'):
            raise ValueError('Estrutura inesperada no pacote de compatibilidade.')
        target = game.joinpath(*rel.parts[2:])
        if game.resolve() not in target.resolve().parents:
            raise ValueError('Destino fora da pasta de teste do jogo.')
        total += item.file_size
        if total > 40_000_000:
            raise ValueError('Pacote de compatibilidade excede o tamanho previsto.')
        plan.append((item, target))
    required = {'version.dll', 'scripts/SplinterCellConviction.FusionFix.asi',
                'scripts/SplinterCellConviction.FusionFix.ini'}
    if not required.issubset({str(p.relative_to(game)) for _, p in plan}):
        raise ValueError('Pacote de compatibilidade incompleto.')
    return plan


def set_values(text, values):
    for key, value in values.items():
        text = re.sub(r'(?mi)^(\s*' + re.escape(key) + r'\s*=\s*)[^\r\n/;]*',
                      lambda match: match[1] + str(value) + ' ', text)
    return text


def video_settings(text):
    values = {'StartupFullscreen': 'False', 'FullscreenViewportX': 1280,
              'FullscreenViewportY': 720, 'WindowedViewportX': 1280, 'WindowedViewportY': 720}
    text = set_values(text, values)
    section = re.search(r'(?mi)^\[DefaultVideoOptions\][^\r\n]*', text)
    if not section:
        return text.rstrip() + '\n\n[DefaultVideoOptions]\n' + ''.join(f'{k}={v}\n' for k, v in values.items())
    end = re.search(r'(?m)^\[', text[section.end():])
    offset = section.end() + end.start() if end else len(text)
    body = text[section.end():offset]
    missing = {k: v for k, v in values.items() if not re.search(r'(?mi)^\s*' + k + r'\s*=', body)}
    return text[:offset].rstrip() + '\n' + ''.join(f'{k}={v}\n' for k, v in missing.items()) + text[offset:]


def prepare(game, prefix, data, archive_path):
    executable = game / 'Conviction_game.exe'
    if not executable.is_file() or sha256(executable) != EXE_SHA256:
        raise ValueError('Esta edição de Conviction ainda não foi validada pelo perfil BTP; executável preservado.')
    if (prefix.resolve() / 'drive_c') not in game.resolve().parents:
        raise ValueError('O perfil Conviction requer uma cópia dentro do prefixo; não use --link.')
    if sha256(archive_path) != FIX_SHA256:
        raise ValueError('A versão do FusionFix mudou ou o download está incompleto; nenhuma correção aplicada.')
    with zipfile.ZipFile(archive_path) as archive:
        plan = payload_plan(archive, game)
        # Lê e valida CRCs antes de iniciar a troca dos componentes.
        contents = [(target, archive.read(item)) for item, target in plan]
    program_ini = prefix / 'drive_c/ProgramData/Ubisoft/Conviction/ConvictionUserPC.ini'
    local_ini = game / 'ConvictionUserPC.ini'
    backup = data / 'Backups' / ('Conviction-profile-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
    backup.mkdir(parents=True)
    saved = set()
    changed = set()

    def preserve(path):
        changed.add(path)
        if path in saved or not path.exists():
            return
        relative = path.relative_to(prefix)
        destination = backup / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)
        saved.add(path)

    try:
        for target, content in contents:
            preserve(target)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
        fix_ini = game / 'scripts/SplinterCellConviction.FusionFix.ini'
        text = fix_ini.read_bytes().decode('utf-8-sig')
        fix_ini.write_text(set_values(text, {
            'SkipSystemDetection': 1, 'WindowedMode': 1, 'FPSLimit': 60,
            'ForceCPUAffinityToAllCores': 0, 'BlacklistControlScheme': 0, 'UnlockDLC': 0,
        }))
        for ini in (local_ini, program_ini):
            if not ini.exists() and local_ini.exists():
                ini.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(local_ini, ini)
            if ini.exists():
                preserve(ini)
                text = ini.read_bytes().decode('latin-1')
                ini.write_bytes(video_settings(text).encode('latin-1'))
        record = {'profile': 'conviction-windowed-metal', 'status': 'experimental',
                  'exe_sha256': EXE_SHA256, 'fusionfix_sha256': FIX_SHA256,
                  'source': FIX_URL, 'backup': str(backup),
                  'verified_scope': 'Cena inicial/tutorial local; não valida toda a campanha, áudio ou controle físico.'}
        (data / 'Registros').mkdir(exist_ok=True)
        (data / 'Registros/conviction-profile.json').write_text(json.dumps(record, ensure_ascii=False, indent=2))
    except Exception:
        # Restore files already touched; retain newly created files in the backup
        # instead of discarding them. Never remove the original game executable.
        for target in changed:
            original = backup / target.relative_to(prefix)
            if original.exists():
                shutil.copy2(original, target)
            elif target.exists():
                failed = backup / 'Failed-new-files' / target.relative_to(prefix)
                failed.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(target), str(failed))
        raise
    print('Perfil Conviction preparado: Metal em janela + FusionFix; teste a partida. Backup:', backup)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', required=True, type=Path)
    parser.add_argument('--prefix', required=True, type=Path)
    parser.add_argument('--data', required=True, type=Path)
    args = parser.parse_args()
    # Não baixar nem alterar configurações de uma edição desconhecida.
    if sha256(args.game / 'Conviction_game.exe') != EXE_SHA256:
        raise ValueError('Edição de Conviction não validada por este perfil; aplicativo anterior preservado.')
    cache = args.data / 'Components'
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / ('FusionFix-' + FIX_SHA256 + '.zip')
    if not archive.exists() or sha256(archive) != FIX_SHA256:
        with tempfile.TemporaryDirectory(prefix='fusionfix-', dir=cache) as temporary:
            download = Path(temporary) / 'download.zip'
            with urllib.request.urlopen(FIX_URL, timeout=30) as response, download.open('wb') as stream:
                shutil.copyfileobj(response, stream, length=1024 * 1024)
            if sha256(download) != FIX_SHA256:
                raise ValueError('Checksum FusionFix inesperado; aplicativo anterior preservado.')
            download.replace(archive)
    prepare(args.game, args.prefix, args.data, archive)


if __name__ == '__main__':
    main()
