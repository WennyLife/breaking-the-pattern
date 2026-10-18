#!/usr/bin/env python3
"""Gerenciamento seguro de componentes e plugins de compatibilidade do BTP.

Fontes oficiais e previsíveis, verificação por SHA256, extração segura sem travessia
de caminhos e backups completos de qualquer arquivo preexistente.
"""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile

HERE = Path(__file__).resolve().parent
MANIFEST_PATH = HERE / 'compatibility-components.json'
CACHE_DIR = Path(os.environ.get('BTP_COMPONENT_CACHE', Path.home() / 'Library/Caches/Breaking the Pattern/Downloads'))


def load_manifest():
    if not MANIFEST_PATH.is_file():
        raise FileNotFoundError(f'Manifesto de componentes ausente: {MANIFEST_PATH}')
    data = json.loads(MANIFEST_PATH.read_text())
    if data.get('schema') != 1:
        raise ValueError('Esquema incompatível no manifesto de componentes.')
    return data['components']


def sha256_of_file(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def ensure_download(component, cache_dir=None):
    """Obtém o pacote do cache ou baixa da fonte oficial com verificação estrita de SHA256."""
    cache = Path(cache_dir) if cache_dir else CACHE_DIR
    cache.mkdir(parents=True, exist_ok=True)
    expected_hash = component['sha256']
    expected_size = component['size']
    url = component['url']

    if not url.startswith('https://github.com/') or '/releases/' not in url:
        raise ValueError(f'Origem não autorizada para o componente {component["id"]}: {url}')

    ext = '.zip' if url.endswith('.zip') else ('.tar.xz' if url.endswith('.tar.xz') else '.tar.gz')
    cached_file = cache / (expected_hash + ext)

    if cached_file.is_file():
        if cached_file.stat().st_size == expected_size and sha256_of_file(cached_file) == expected_hash:
            return cached_file

    with tempfile.TemporaryDirectory(prefix='.download-', dir=cache) as tmp_dir:
        part = Path(tmp_dir) / ('download' + ext)
        subprocess.run([
            '/usr/bin/curl', '--fail', '--location', '--proto', '=https',
            '--proto-redir', '=https', '--connect-timeout', '20', '--max-time', '600',
            '--retry', '2', '--max-filesize', str(expected_size + 1048576),
            '--silent', '--show-error', '--output', str(part), url
        ], check=True)

        if part.stat().st_size != expected_size or sha256_of_file(part) != expected_hash:
            raise ValueError(f'Verificação criptográfica falhou para {component["id"]}; integridade preservada.')

        part.replace(cached_file)

    return cached_file


def validate_zip_payload(archive, component):
    """Garante que nenhum caminho escape da pasta ou contenha links maliciosos."""
    total_size = 0
    members = []
    for info in archive.infolist():
        rel = PurePosixPath(info.filename)
        if rel.is_absolute() or '..' in rel.parts or '\\' in info.filename:
            raise ValueError('Caminho inválido detectado no arquivo de plugin.')
        if stat.S_ISLNK(info.external_attr >> 16):
            raise ValueError('Links simbólicos não são permitidos em arquivos de plugins.')
        if not info.is_dir():
            total_size += info.file_size
            members.append(info)

    if total_size > component.get('unpacked_limit', 50_000_000):
        raise ValueError(f'Tamanho descompactado excede limite de segurança: {total_size}')

    return members


def is_satisfied(component_id, target_dir):
    """Verifica se os arquivos necessários do componente já estão presentes no destino."""
    components = load_manifest()
    component = components.get(component_id)
    if not component:
        raise KeyError(f'Componente desconhecido: {component_id}')

    target = Path(target_dir)
    required = component.get('required_files', [])
    for rel_path in required:
        file_path = target / rel_path
        if not file_path.is_file() or file_path.stat().st_size == 0:
            return False
    return True


def provision_component(component_id, target_dir, backup_root=None, cache_dir=None):
    """Instala o componente no diretório de destino com backup de quaisquer arquivos preexistentes."""
    components = load_manifest()
    component = components.get(component_id)
    if not component:
        raise KeyError(f'Componente desconhecido: {component_id}')

    target = Path(target_dir).resolve()
    if not target.is_dir():
        raise NotADirectoryError(f'Diretório de destino inexistente: {target}')

    # Se já estiver satisfeito, registra que nenhuma alteração é necessária
    if is_satisfied(component_id, target):
        return {
            'component_id': component_id,
            'status': 'already_satisfied',
            'installed_files': [],
            'backups': []
        }

    archive_path = ensure_download(component, cache_dir)
    timestamp = datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup_dir = (Path(backup_root) if backup_root else target) / 'Backups/Components' / f'{component_id}-{timestamp}'

    installed = []
    backups = []

    with zipfile.ZipFile(archive_path) as archive:
        validate_zip_payload(archive, component)
        mapping = component.get('mapping', {})

        # Caso especial do GTA SA vorbisFile -> vorbisHooked:
        # Se vorbisFile.dll preexistir e não for o ASI loader, guardá-lo como vorbisHooked.dll
        if component_id == 'gtasa-widescreen-fix':
            target_vorbis = target / 'vorbisFile.dll'
            hooked_vorbis = target / 'vorbisHooked.dll'
            if target_vorbis.is_file() and not hooked_vorbis.is_file():
                # É a DLL original do jogo que precisa ser preservada para forward calls
                backup_dir.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target_vorbis, backup_dir / 'vorbisFile.dll.orig')
                shutil.copy2(target_vorbis, hooked_vorbis)
                backups.append(str(backup_dir / 'vorbisFile.dll.orig'))

        for src_in_zip, rel_dest in mapping.items():
            dest_file = target / rel_dest
            try:
                content = archive.read(src_in_zip)
            except KeyError:
                continue

            if dest_file.is_file():
                backup_dir.mkdir(parents=True, exist_ok=True)
                b_file = backup_dir / rel_dest
                b_file.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(dest_file, b_file)
                backups.append(str(b_file))

            dest_file.parent.mkdir(parents=True, exist_ok=True)
            dest_file.write_bytes(content)
            installed.append(str(dest_file.relative_to(target)))

    return {
        'component_id': component_id,
        'status': 'provisioned',
        'installed_files': installed,
        'backups': backups,
        'version': component.get('version'),
        'sha256': component['sha256']
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--list', action='store_true', help='Lista componentes disponíveis')
    parser.add_argument('--check', help='ID do componente para verificar se está instalado')
    parser.add_argument('--ensure', help='ID do componente para baixar e instalar')
    parser.add_argument('--target', type=Path, help='Diretório do jogo de destino')
    parser.add_argument('--backup-dir', type=Path, help='Diretório para backups')
    parser.add_argument('--cache-dir', type=Path, help='Diretório de cache customizado')
    args = parser.parse_args()

    if args.list:
        manifest = load_manifest()
        print(json.dumps(manifest, indent=2, ensure_ascii=False))
        return

    if args.check:
        if not args.target:
            raise SystemExit('BTP: --target obrigatório para --check')
        satisfied = is_satisfied(args.check, args.target)
        print(json.dumps({'component_id': args.check, 'satisfied': satisfied}))
        sys.exit(0 if satisfied else 1)

    if args.ensure:
        if not args.target:
            raise SystemExit('BTP: --target obrigatório para --ensure')
        result = provision_component(args.ensure, args.target, args.backup_dir, args.cache_dir)
        print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        raise SystemExit(f'BTP: {error}')
