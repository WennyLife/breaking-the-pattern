#!/usr/bin/env python3
"""Publica um build BTP já validado, preservando apps, acervo e inventário anteriores."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid
import zipfile


def digest(path):
    with path.open('rb') as stream:
        result = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
        return result.hexdigest()


def exists(path):
    return path.exists() or path.is_symlink()


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def verify(app):
    run('/usr/bin/plutil', '-lint', app / 'Contents/Info.plist')
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
    forbidden = {'.exe', '.dll', '.asi', '.txd', '.gxt'}
    if any(p.suffix.lower() in forbidden for p in app.rglob('*')):
        raise RuntimeError('O pacote BTP contém binários ou dados de jogo inesperados.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--install-dir', type=Path, default=Path.home() / 'Applications')
    parser.add_argument('--archive-root', type=Path, default=Path.home() / 'Movies/Apps criados')
    args = parser.parse_args()
    app, project = args.app.resolve(), args.project.resolve()
    verify(app)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'org.lendaii.breakingthepattern':
        raise RuntimeError('O publicador aceita somente o aplicativo Breaking the Pattern.')
    name = 'Breaking the Pattern'
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    archive = args.archive_root / name
    installed = args.install_dir / app.name
    index = args.archive_root / 'inventario.json'
    old_index = index.read_bytes() if index.exists() else None
    inventory = json.loads(old_index) if old_index else []
    if not isinstance(inventory, list) or not all(isinstance(entry, dict) for entry in inventory):
        raise RuntimeError('Formato de inventário desconhecido; publicação interrompida.')
    args.install_dir.mkdir(parents=True, exist_ok=True)
    args.archive_root.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:6]
    backup = archive / 'Backups' / (version + '-' + stamp)

    # Todas as cópias e verificações acontecem antes de substituir versões atuais.
    with tempfile.TemporaryDirectory(prefix='.btp-release-', dir=args.archive_root) as temporary, \
         tempfile.TemporaryDirectory(prefix='.btp-install-', dir=args.install_dir) as install_temporary:
        stage = Path(temporary)
        for folder in ('App', 'Instaladores', 'Codigo', 'Registros'):
            (stage / folder).mkdir()
        staged_app = stage / 'App' / app.name
        install_stage = Path(install_temporary) / app.name
        run('/usr/bin/ditto', '--norsrc', app, staged_app)
        run('/usr/bin/ditto', '--norsrc', app, install_stage)
        verify(staged_app)
        verify(install_stage)
        package_name = f'{name}-{version}.zip'
        package = stage / 'Instaladores' / package_name
        run('/usr/bin/ditto', '-c', '-k', '--norsrc', '--keepParent', staged_app, package)
        with zipfile.ZipFile(package) as contents:
            if contents.testzip() is not None:
                raise RuntimeError('ZIP inválido; versões atuais preservadas.')
        unpacked = stage / 'ZipValidation'
        run('/usr/bin/ditto', '-x', '-k', package, unpacked)
        verify(unpacked / app.name)
        (stage / 'Codigo' / 'Projeto original').symlink_to(project, target_is_directory=True)
        shutil.copy2(app / 'Contents/Resources/Build.json', stage / 'Codigo' / 'Build.json')
        record = {
            'app': name,
            'versao_instalada': version,
            'build': build,
            'instalado_em': str(installed),
            'projeto': str(project),
            'pasta': str(archive),
            'instaladores': [{'arquivo': str(archive / 'Instaladores' / package_name),
                             'sha256': digest(package), 'origem': str(app)}],
            'executavel_sha256': digest(app / 'Contents/MacOS' / info['CFBundleExecutable']),
            'validacao': ['Build Swift arm64', 'Assinatura ad hoc verificada',
                          'ZIP íntegro e app extraído com assinatura verificada',
                          'Pacote BTP sem executáveis, dados ou saves dos jogos'],
            'limitacoes': ['DMG desta versão não gerado; pacote ZIP disponível.',
                          'Assinatura ad hoc local, sem notarização.',
                          'Validação deste pacote não comprova compatibilidade ou FPS dos jogos.',
                          'Preparação de jogos ainda depende do runtime doador instalado separadamente.'],
            'atualizado_em': datetime.now(timezone.utc).isoformat(),
        }
        (stage / 'Registros' / 'inventario.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')
        (stage / 'Registros' / 'validacao.txt').write_text(
            '\n'.join(record['validacao'] + [''] + record['limitacoes']) + '\n')
        # Não substitua alterações de inventário realizadas durante o empacotamento.
        if (index.read_bytes() if index.exists() else None) != old_index:
            raise RuntimeError('Inventário mudou durante a preparação; tente novamente.')
        updated = [entry for entry in inventory if entry.get('app') != name] + [record]
        staged_index = stage / 'inventario.json'
        staged_index.write_text(json.dumps(updated, ensure_ascii=False, indent=2) + '\n')

        moved, published = [], []

        def preserve(path, destination):
            if exists(path):
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(path), str(destination))
                moved.append((path, destination))

        try:
            archive.mkdir(parents=True, exist_ok=True)
            preserve(installed, backup / 'Instalado' / app.name)
            for folder in ('App', 'Instaladores', 'Codigo', 'Registros'):
                destination = archive / folder
                preserve(destination, backup / 'Acervo' / folder)
                os.replace(stage / folder, destination)
                published.append(destination)
            os.replace(install_stage, installed)
            published.append(installed)
            # Recolhe somente o antigo BTP solto; outros aplicativos ficam intactos.
            preserve(args.archive_root / app.name, backup / 'Legado' / app.name)
            if old_index is not None:
                (backup / 'Registros').mkdir(parents=True, exist_ok=True)
                (backup / 'Registros' / 'inventario-anterior.json').write_bytes(old_index)
            os.replace(staged_index, index)
        except BaseException:
            for path in reversed(published):
                if path.is_dir() and not path.is_symlink():
                    shutil.rmtree(path)
                elif exists(path):
                    path.unlink()
            for path, destination in reversed(moved):
                if exists(destination) and not exists(path):
                    path.parent.mkdir(parents=True, exist_ok=True)
                    shutil.move(str(destination), str(path))
            raise
        print(f'Instalado: {installed}\nAcervo: {archive}\nPacote: {archive / "Instaladores" / package_name}')
        print(f'Backups preservados: {backup}')


if __name__ == '__main__':
    main()
