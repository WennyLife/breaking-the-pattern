#!/usr/bin/env python3
"""Componentes versionados do BTP. Não procura nem copia aplicativos de jogos."""
import argparse
from contextlib import contextmanager
from datetime import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import plistlib
import posixpath
import shutil
import subprocess
import sys
import tarfile
import tempfile

HERE = Path(__file__).resolve().parent
MANIFEST = json.loads((HERE / 'runtime-manifest.json').read_text())
LAYOUT_VERSION = 3
CACHE = Path(os.environ.get('BTP_COMPONENT_CACHE', Path.home() / 'Library/Caches/Breaking the Pattern/Downloads'))


def say(message):
    print('[1/5] ' + message, file=sys.stderr, flush=True)


def sha256(path):
    result = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def download(component):
    url, digest = component['url'], component['sha256']
    if not url.startswith('https://github.com/') or '/releases/download/' not in url:
        raise ValueError('Origem de componente não permitida.')
    CACHE.mkdir(parents=True, exist_ok=True)
    target = CACHE / (digest + ('.tar.gz' if url.endswith('.gz') else '.tar.xz'))
    if target.is_file() and target.stat().st_size == component['size'] and sha256(target) == digest:
        return target
    with tempfile.TemporaryDirectory(prefix='.download-', dir=CACHE) as temporary:
        partial = Path(temporary) / 'component'
        say('Baixando componente ' + component['version'] + '…')
        subprocess.run(['/usr/bin/curl', '--fail', '--location', '--proto', '=https',
                        '--proto-redir', '=https', '--connect-timeout', '20', '--max-time', '900',
                        '--retry', '2', '--max-filesize', str(component['size']),
                        '--silent', '--show-error', '--output', str(partial), url], check=True)
        if partial.stat().st_size != component['size'] or sha256(partial) != digest:
            raise ValueError('Download incompleto ou checksum inesperado; versão atual preservada.')
        partial.replace(target)
    return target


def extract(archive, destination, limit, excluded=()):
    """Valida o plano inteiro antes de escrever, inclusive links e tipos especiais."""
    with tarfile.open(archive) as contents:
        members = contents.getmembers()
        if sum(item.size for item in members) > limit or len(members) > 50000:
            raise ValueError('Arquivo expandido excede o limite do componente.')
        links = set()
        names = set()
        symlinks = {}
        for item in members:
            rel = PurePosixPath(item.name)
            if rel.is_absolute() or '..' in rel.parts or '\\' in item.name or not rel.parts:
                raise ValueError('Caminho inválido no componente.')
            if rel in names:
                raise ValueError('Caminho duplicado no componente.')
            names.add(rel)
            if not (item.isfile() or item.isdir() or item.issym() or item.islnk()):
                raise ValueError('Tipo de arquivo não permitido no componente.')
            if item.issym() or item.islnk():
                name = item.linkname
                resolved = posixpath.normpath(str(rel.parent / name) if item.issym() else name)
                if name.startswith('/') or '\\' in name or resolved == '..' or resolved.startswith('../'):
                    raise ValueError('Link fora da pasta do componente.')
                links.add(rel)
                if item.issym():
                    symlinks[rel] = name
        def resolve_links(parts):
            pending, resolved, hops = list(parts), [], 0
            while pending:
                part = pending.pop(0)
                if part in ('', '.'):
                    continue
                if part == '..':
                    if not resolved:
                        raise ValueError('Cadeia de links fora do componente.')
                    resolved.pop()
                    continue
                resolved.append(part)
                link = symlinks.get(PurePosixPath(*resolved))
                if link is not None:
                    hops += 1
                    if hops > 40:
                        raise ValueError('Ciclo de links no componente.')
                    resolved.pop()
                    pending = link.split('/') + pending
        for item in members:
            if any(parent in links for parent in PurePosixPath(item.name).parents):
                raise ValueError('Extração através de link não permitida.')
            if item.issym() or item.islnk():
                path = PurePosixPath(item.name).parent / item.linkname if item.issym() else PurePosixPath(item.linkname)
                resolve_links(path.parts)
            target = (destination / item.name).resolve()
            if target != destination.resolve() and destination.resolve() not in target.parents:
                raise ValueError('Destino de extração fora do componente.')
        accepted = [item for item in members if not any(
            item.name == prefix or item.name.startswith(prefix + '/') for prefix in excluded)]
        destination.mkdir(parents=True, exist_ok=True)
        # Python embarcado tem data_filter; no Python de build antigo o plano
        # acima restringe caminhos, links e tipos antes de extractall.
        options = {'filter': 'data'} if sys.version_info >= (3, 12) else {}
        contents.extractall(destination, members=accepted, **options)


@contextmanager
def locked(root):
    root.mkdir(parents=True, exist_ok=True)
    with (root / '.install.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def stage_python(destination):
    component = MANIFEST['components']['python']
    with tempfile.TemporaryDirectory(prefix='btp-python-') as temporary:
        root = Path(temporary)
        extract(download(component), root, component['unpacked_limit'])
        python = root / 'python'
        # pip não participa da operação do BTP; não embarcar seus launchers Windows.
        for path in list(python.rglob('*.exe')):
            path.unlink()
        subprocess.run(['/usr/bin/ditto', '--norsrc', str(python), str(destination)], check=True)
    subprocess.run([str(destination / 'bin/python3'), '-I', '-B', '-c', 'import ssl,tarfile,json;print("Python BTP disponível")'], check=True)


def required(resources):
    return [resources / relative for relative in (
        'GameRuntime.app/Contents/MacOS/wine', 'RuntimeBootstrap', 'x87sidecar',
        'wine/bin/wineserver', 'GameRuntime.app/Contents/lib/wine/x86_64-unix/ntdll.so',
        'wine/lib/wine/d3d9/mtld3d/i386-windows/d3d9.dll',
        'Underground 2 FPS.app/Contents/MacOS/Underground2FPS')]


def ready(resources):
    record = resources / 'Runtime.json'
    if not record.is_file():
        return False
    try:
        state = json.loads(record.read_text())
        return state.get('layout_version') == LAYOUT_VERSION and state['manifest_sha256'] == sha256(HERE / 'runtime-manifest.json') and all(
            path.is_file() and sha256(path) == state['files'][str(path.relative_to(resources))]
            for path in required(resources))
    except (OSError, ValueError, KeyError):
        return False


def system_ready():
    if platform.system() != 'Darwin' or platform.machine() not in ('arm64', 'aarch64'):
        raise RuntimeError('Este pacote do BTP exige um Mac Apple Silicon.')
    version = subprocess.check_output(['/usr/bin/sw_vers', '-productVersion'], text=True).strip()
    if int(version.split('.')[0]) < MANIFEST['minimum_macos']:
        raise RuntimeError('O motor selecionado exige macOS15 ou posterior.')
    rosetta = subprocess.run(['/usr/bin/arch', '-x86_64', '/usr/bin/true'], capture_output=True)
    if rosetta.returncode:
        raise RuntimeError('Instale a Rosetta pelo aviso do macOS e tente novamente. BTP não aceita os termos por você.')


def ensure_runtime(root, support):
    system_ready()
    final = root / MANIFEST['runtime_id']
    resources = final / 'Resources'
    with locked(root):
        if ready(resources):
            return resources
        with tempfile.TemporaryDirectory(prefix='.install-', dir=root) as temporary:
            stage = Path(temporary) / 'runtime'
            out = stage / 'Resources'
            runtime = out / 'GameRuntime.app'
            runtime_resources = runtime / 'Contents/Resources'
            runtime_resources.mkdir(parents=True)
            component = MANIFEST['components']['wine']
            say('Preparando motor independente e verificando arquivos…')
            # A primeira distribuição BTP é D3D9. Não empacotar os componentes
            # Apple D3DMetal/GPTK que acompanham o arquivo upstream completo.
            extract(download(component), runtime_resources, component['unpacked_limit'], (
                'wine/lib/wine/dxgi/gptk', 'wine/lib/external/D3DMetal.framework',
                'wine/lib/external/D3DMetal-License.rtf'))
            wine = runtime_resources / 'wine'
            macos = runtime / 'Contents/MacOS'
            macos.mkdir()
            # Loader Wine com reserva de endereços para processos Windows 32 bits.
            # bin/wine é o despachante: movê-lo para um .app impede sua reexecução
            # no loader correto e causa c0000017 antes mesmo do wineboot.
            shutil.copy2(wine / 'lib/wine/x86_64-unix/wine', macos / 'wine')
            (macos / 'ntdll.so').symlink_to('../Resources/wine/lib/wine/x86_64-unix/ntdll.so')
            (runtime / 'Contents/lib').symlink_to('Resources/wine/lib')
            (runtime / 'Contents/share').symlink_to('Resources/wine/share')
            info = {'CFBundleIdentifier': 'org.lendaii.btp.runtime', 'CFBundleExecutable': 'wine',
                    'CFBundleName': 'BTP Game Runtime', 'CFBundlePackageType': 'APPL',
                    'CFBundleShortVersionString': '0.2.0', 'CFBundleVersion': '4',
                    'NSHighResolutionCapable': False,
                    'NSBluetoothAlwaysUsageDescription': 'Usar o controle conectado ao Mac.'}
            (runtime / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
            (out / 'wine').symlink_to('GameRuntime.app/Contents/Resources/wine')
            sidecar = MANIFEST['components']['x87']
            extract(download(sidecar), out, sidecar['unpacked_limit'])
            shutil.copy2(support / 'RuntimeBootstrap', out / 'RuntimeBootstrap')
            fps = out / 'Underground 2 FPS.app/Contents'
            (fps / 'MacOS').mkdir(parents=True)
            shutil.copy2(support / 'Underground2FPS', fps / 'MacOS/Underground2FPS')
            fps_info = {'CFBundleIdentifier': 'org.lendaii.btp.fps', 'CFBundleExecutable': 'Underground2FPS',
                        'CFBundleName': 'BTP FPS', 'CFBundlePackageType': 'APPL', 'LSUIElement': True,
                        'CFBundleShortVersionString': '0.2.0', 'CFBundleVersion': '4'}
            (fps / 'Info.plist').write_bytes(plistlib.dumps(fps_info))
            for app in (runtime, fps.parent):
                subprocess.run(['/usr/bin/codesign', '--force', '--deep', '--sign', '-', str(app)], check=True, stderr=sys.stderr)
                subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True)
            state = {'runtime_id': MANIFEST['runtime_id'], 'layout_version': LAYOUT_VERSION, 'manifest_sha256': sha256(HERE / 'runtime-manifest.json'),
                     'components': MANIFEST['components'], 'files': {
                         str(path.relative_to(out)): sha256(path) for path in required(out)}}
            (out / 'Runtime.json').write_text(json.dumps(state, indent=2) + '\n')
            (out / 'Attributions.txt').write_text('Wine: LGPL; x87sidecar: MIT.\nFontes e versões: Runtime.json.\n'
                'mtld3d é fornecido pelo build Wine fixado. D3DMetal/GPTK não incluídos nesta instalação BTP.\n')
            if not ready(out):
                raise RuntimeError('Motor incompleto; instalação anterior preservada.')
            if final.exists():
                backup = root / 'Backups' / (MANIFEST['runtime_id'] + '-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
                backup.parent.mkdir(exist_ok=True)
                final.rename(backup)
                try:
                    stage.rename(final)
                except BaseException:
                    backup.rename(final)
                    raise
            else:
                stage.rename(final)
    say('Motor independente pronto.')
    return resources


def initialize_prefix(resources, prefix):
    if prefix.exists():
        if (prefix / 'system.reg').is_file() and (prefix / 'drive_c').is_dir():
            return
        raise RuntimeError('Prefixo existente incompleto; preservado para diagnóstico: ' + str(prefix))
    prefix.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.prefix-', dir=prefix.parent) as temporary:
        root = Path(temporary)
        target = root / 'prefix'
        log_path = prefix.parent / 'Registros/runtime-initialization.log'
        log_path.parent.mkdir(parents=True, exist_ok=True)
        env = dict(os.environ, WINEPREFIX=str(target), WINEARCH='wow64', WINELOADERNOEXEC='1',
                   WINEDEBUG='-all', WINESERVER=str(resources / 'wine/bin/wineserver'),
                   WINEDLLOVERRIDES='mscoree=;mshtml=;winemenubuilder.exe=', MallocNanoZone='0', LC_ALL='C.UTF-8')
        command = [str(resources / 'RuntimeBootstrap'), str(root / 'wine.pid'),
                   str(resources / 'x87sidecar'), '--cooperative',
                   str(resources / 'GameRuntime.app/Contents/MacOS/wine'), 'wineboot', '-u']
        say('Criando ambiente Windows limpo para este jogo…')
        with log_path.open('wb') as log:
            try:
                # Mesmos limites de pilha do launcher, sem alterar o processo GUI.
                result = subprocess.run(['/bin/bash', '-c', 'ulimit -s 65520; exec "$@"', 'btp', *command],
                                        env=env, stdout=log, stderr=log, timeout=120)
                if result.returncode:
                    raise RuntimeError('Falha ao iniciar ambiente (código ' + str(result.returncode) + '); registro: ' + str(log_path))
                subprocess.run([str(resources / 'wine/bin/wineserver'), '-w'], env=env,
                               stdout=log, stderr=log, check=True, timeout=45)
            finally:
                subprocess.run([str(resources / 'wine/bin/wineserver'), '-k'], env=env,
                               stdout=log, stderr=log, timeout=15)
        if not (target / 'system.reg').is_file():
            raise RuntimeError('Ambiente Windows não foi criado; registro: ' + str(log_path))
        # Novos ambientes guardam documentos/saves dentro do próprio prefixo.
        # Não reutilizar atalhos que o wineboot cria para as pastas pessoais do Mac.
        for user in (target / 'drive_c/users').iterdir():
            if user.is_dir():
                for name in ('Documents', 'Downloads', 'Music', 'Pictures', 'Videos', 'Desktop'):
                    folder = user / name
                    if folder.is_symlink():
                        folder.unlink()
                        folder.mkdir()
        target.rename(prefix)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage-python', type=Path)
    parser.add_argument('--ensure', action='store_true')
    parser.add_argument('--root', type=Path, default=Path(os.environ.get('BTP_RUNTIME_HOME',
        Path.home() / 'Library/Application Support/Breaking the Pattern/Runtimes')))
    parser.add_argument('--support', type=Path, default=HERE / 'RuntimeTools')
    parser.add_argument('--init-prefix', type=Path)
    parser.add_argument('--resources', type=Path)
    args = parser.parse_args()
    if args.stage_python:
        stage_python(args.stage_python)
    elif args.init_prefix:
        initialize_prefix(args.resources, args.init_prefix)
    elif args.ensure:
        print(ensure_runtime(args.root, args.support))
    else:
        parser.error('Escolha --ensure, --init-prefix ou --stage-python.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('BTP: ' + str(error), file=sys.stderr)
        sys.exit(1)
