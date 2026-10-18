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


def guard_path(target_root, path):
    """Verifica estritamente que nenhum ancestral ou componente do caminho seja link simbólico,
    e que o destino final permaneça sob a raiz privada alvo."""
    root_resolved = Path(target_root).resolve()
    p = Path(path)
    if not p.is_absolute():
        p = root_resolved / p
    else:
        p_str = str(p)
        root_str = str(root_resolved)
        if p_str.startswith('/var/') and root_str.startswith('/private/var/'):
            p = Path('/private' + p_str)
        elif p_str.startswith('/tmp/') and root_str.startswith('/private/tmp/'):
            p = Path('/private' + p_str)
        elif p_str.startswith('/private/var/') and root_str.startswith('/var/'):
            root_resolved = Path('/private' + root_str)
        elif p_str.startswith('/private/tmp/') and root_str.startswith('/tmp/'):
            root_resolved = Path('/private' + root_str)

    try:
        rel = p.relative_to(root_resolved)
    except ValueError:
        raise ValueError(f'Caminho escapa da raiz privada de destino: {p}')

    cur = root_resolved
    for part in rel.parts:
        cur = cur / part
        if os.path.islink(cur):
            raise ValueError(f'Link simbólico detectado no caminho de destino: {cur}. Recusando escrita fora da raiz privada.')
        if cur.exists():
            try:
                cur.resolve().relative_to(root_resolved)
            except ValueError:
                raise ValueError(f'Caminho escapa da raiz privada de destino: {cur}')
    return cur


class ComponentTransaction:
    """Controla transação de escrita de arquivos com rollback automático em falhas."""
    def __init__(self, target_root, backup_root):
        self.target_root = Path(target_root).resolve()
        self.backup_root = Path(backup_root).resolve()
        self.created_files = []
        self.created_dirs = []
        self.backups = {}
        self.committed = False

    def stage_file_copy(self, src_file, dest_file):
        dest_path = guard_path(self.target_root, dest_file)
        src_path = Path(src_file).resolve()
        if dest_path in self.created_files:
            pass
        elif dest_path.is_file() and not os.path.islink(dest_path):
            if dest_path not in self.backups:
                backup_path = self.backup_root / dest_path.relative_to(self.target_root)
                backup_path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(dest_path, backup_path)
                self.backups[dest_path] = backup_path
        else:
            self._ensure_parent_dirs(dest_path)
            self.created_files.append(dest_path)
        shutil.copy2(src_path, dest_path)

    def _ensure_parent_dirs(self, dest_path):
        d = dest_path.parent
        dirs_to_create = []
        while d != self.target_root and not d.exists():
            dirs_to_create.append(d)
            d = d.parent
        for created_d in reversed(dirs_to_create):
            created_d.mkdir(parents=True, exist_ok=True)
            self.created_dirs.append(created_d)

    def stage_file_write(self, dest_file, content):
        dest_path = guard_path(self.target_root, dest_file)
        if dest_path in self.created_files:
            pass
        elif dest_path.is_file() and not os.path.islink(dest_path):
            if dest_path not in self.backups:
                backup_path = self.backup_root / dest_path.relative_to(self.target_root)
                backup_path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(dest_path, backup_path)
                self.backups[dest_path] = backup_path
        else:
            self._ensure_parent_dirs(dest_path)
            self.created_files.append(dest_path)
        dest_path.write_bytes(content)

    def rollback(self):
        for f in reversed(self.created_files):
            try:
                if f.is_file() or os.path.islink(f):
                    f.unlink()
            except OSError:
                pass
        for dest_path, backup_path in self.backups.items():
            try:
                if backup_path.is_file():
                    dest_path.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(backup_path, dest_path)
            except OSError:
                pass
        for d in reversed(self.created_dirs):
            try:
                if d.is_dir() and not any(d.iterdir()):
                    d.rmdir()
            except OSError:
                pass

    def commit(self):
        self.committed = True


def preflight_target_paths(component, target_dir):
    """Valida estritamente que nenhum caminho de destino ou diretório intermediário
    seja link simbólico (mesmo que quebrado), e que nenhum arquivo escape da raiz."""
    target_root = Path(target_dir).resolve()
    if not target_root.is_dir():
        raise NotADirectoryError(f'Diretório de destino inválido: {target_root}')

    mapping = component.get('mapping', {})
    paths_to_verify = list(mapping.values())
    if component.get('id') == 'gtasa-widescreen-fix':
        paths_to_verify.append('vorbisHooked.dll')

    for rel in paths_to_verify:
        rel_posix = PurePosixPath(rel)
        if rel_posix.is_absolute() or '..' in rel_posix.parts or '\\' in rel:
            raise ValueError(f'Caminho de destino inválido ou escape detectado: {rel}')

        cur = target_root
        for part in rel_posix.parts:
            cur = cur / part
            if os.path.islink(cur):
                raise ValueError(f'Link simbólico detectado no caminho de destino: {cur}. Recusando escrita fora da raiz privada.')
            if cur.exists():
                try:
                    cur.resolve().relative_to(target_root)
                except ValueError:
                    raise ValueError(f'Caminho de destino escapa da raiz privada: {cur}')


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


def provision_component(component_id, target_dir, backup_root=None, cache_dir=None, transaction=None):
    """Instala o componente no diretório de destino com preflight, staging e transação com rollback."""
    components = load_manifest()
    component = components.get(component_id)
    if not component:
        raise KeyError(f'Componente desconhecido: {component_id}')

    target = Path(target_dir).resolve()
    if not target.is_dir():
        raise NotADirectoryError(f'Diretório de destino inexistente: {target}')

    # Preflight estrito antes de qualquer escrita ou backup
    preflight_target_paths(component, target)

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
    own_transaction = False
    tx = transaction
    if tx is None:
        tx = ComponentTransaction(target, backup_dir)
        own_transaction = True

    try:
        with tempfile.TemporaryDirectory(prefix='btp-component-stage-') as stage_tmp:
            stage_path = Path(stage_tmp)
            with zipfile.ZipFile(archive_path) as archive:
                validate_zip_payload(archive, component)
                archive.extractall(stage_path)

            mapping = component.get('mapping', {})

            # Exige que TODOS os membros mapeados estejam presentes no ZIP descompactado ANTES de tocar o alvo
            missing_members = [src for src in mapping.keys() if not (stage_path / src).is_file()]
            if missing_members:
                raise ValueError(f"Componente {component_id} incompleto: membros ausentes no pacote ZIP: {missing_members}")

            if component_id == 'gtasa-widescreen-fix':
                target_vorbis = target / 'vorbisFile.dll'
                hooked_vorbis = target / 'vorbisHooked.dll'
                if target_vorbis.is_file() and not hooked_vorbis.is_file():
                    tx.stage_file_copy(target_vorbis, hooked_vorbis)

            for src_in_zip, rel_dest in mapping.items():
                staged_file = stage_path / src_in_zip

                dest_file = target / rel_dest
                if dest_file.is_file() and dest_file.suffix.lower() == '.ini':
                    # Preserva configurações existentes do usuário
                    continue

                content = staged_file.read_bytes()

                if component_id == 'nfsu2-widescreen-fix' and rel_dest == 'scripts/NFSUnderground2.WidescreenFix.ini':
                    ini_lines = content.decode('latin-1').splitlines()
                    for i, line in enumerate(ini_lines):
                        k = line.split('=', 1)[0].strip()
                        if k == 'WindowedMode':
                            ini_lines[i] = 'WindowedMode = 4'
                        elif k == 'FPSLimit':
                            ini_lines[i] = 'FPSLimit = 0'
                    content = ('\n'.join(ini_lines) + '\n').encode('latin-1')

                tx.stage_file_write(dest_file, content)
                installed.append(str(dest_file.relative_to(target)))

        if own_transaction:
            tx.commit()
    except Exception as error:
        if own_transaction:
            tx.rollback()
        raise error

    backups_list = [str(b) for b in tx.backups.values()]
    return {
        'component_id': component_id,
        'status': 'provisioned',
        'installed_files': installed,
        'backups': backups_list,
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
