#!/usr/bin/env python3
"""Publish verified CI artifacts. Update signing stays on the maintainer's Mac."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import urllib.error
import urllib.parse
import urllib.request


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    args = parser.parse_args()
    repository = os.environ['GITHUB_REPOSITORY']
    if repository != 'WennyLife/breaking-the-pattern':
        raise ValueError('Release publishing is restricted to the configured repository')
    token = os.environ['GH_TOKEN']
    tag = os.environ['GITHUB_REF_NAME']
    if not re.fullmatch(r'v\d+\.\d+\.\d+', tag):
        raise ValueError('Invalid release tag')
    version = tag[1:]
    app = args.archive / 'App/Breaking the Pattern.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info['CFBundleShortVersionString'] != version:
        raise ValueError('Release tag and built app differ')
    inventory = json.loads((args.archive / 'Registros/inventario.json').read_text())
    assets = []
    for item in inventory['instaladores']:
        path = Path(item['arquivo'])
        if digest(path) != item['sha256']:
            raise ValueError('Installer checksum mismatch: ' + path.name)
        assets.append((path, path.name.replace('Breaking the Pattern', 'Breaking-the-Pattern')))
    if sorted(path.suffix for path, name in assets) != ['.dmg', '.zip']:
        raise ValueError('Expected exactly one ZIP and one DMG')
    output = Path(os.environ['RUNNER_TEMP']) / 'btp-publication'
    output.mkdir()
    sums = output / 'SHA256SUMS.txt'
    sums.write_text(''.join(digest(p) + '  ' + name + '\n' for p, name in assets))
    metadata = output / 'ReleaseMetadata.json'
    metadata.write_text(json.dumps({'version': version, 'build': info['CFBundleVersion'],
        'source_commit': os.environ['GITHUB_SHA'], 'workflow_run': os.environ['GITHUB_RUN_ID'],
        'checksums': {name: digest(p) for p, name in assets},
        'signing': 'Ad hoc app signature. Sparkle Ed25519 signing is performed separately on the maintainer Mac.'}, indent=2) + '\n')
    assets.extend([(sums, sums.name), (metadata, metadata.name)])
    api = 'https://api.github.com/repos/' + repository

    def request(url, method='GET', value=None, payload=None):
        if urllib.parse.urlparse(url).hostname not in ('api.github.com', 'uploads.github.com'):
            raise ValueError('Unexpected GitHub API host')
        data = json.dumps(value).encode() if value is not None else payload
        headers = {'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json',
                   'User-Agent': 'BTP-reviewed-release', 'X-GitHub-Api-Version': '2022-11-28'}
        if data is not None:
            headers['Content-Type'] = 'application/json' if value is not None else 'application/octet-stream'
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        with urllib.request.urlopen(req, timeout=180) as response:
            raw = response.read()
            return json.loads(raw) if raw else None

    try:
        release = request(api + '/releases/tags/' + tag)
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        notes = ('BTP ' + version + ' for Apple Silicon / macOS 15+.\n\n'
                 'English / Português. Prepare your own tested editions of NFS Underground 2 and GTA San Andreas. '
                 'Independent runtime, automatic compatibility components, per-edition recipes, and in-app updates. '
                 'No games or saves included. Consult the compatibility documentation for accepted editions and validation scope.\n\n'
                 'Jogos não incluídos: forneça sua própria pasta. Suporte inicial às edições testadas de NFSU2/GTA SA. '
                 'Splinter Cell is not included in this release.\n\n'
                 'The application is ad hoc signed, not Apple-notarized. '
                 'Independent validation on another physical Mac remains pending. '
                 'No universal compatibility or sustained FPS guarantee. '
                 'SHA256 checksums and build/source metadata are attached.')
        release = request(api + '/releases', 'POST', {'tag_name': tag, 'name': 'BTP ' + version,
                          'target_commitish': os.environ['GITHUB_SHA'], 'draft': True,
                          'prerelease': False, 'body': notes})
    if not release['draft']:
        raise ValueError('This tag already has a public release; do not overwrite it')
    for path, name in assets:
        prior = next((a for a in release['assets'] if a['name'] == name), None)
        if prior:
            # Only this draft's exact managed filenames may be replaced on retry.
            request(api + '/releases/assets/' + str(prior['id']), 'DELETE')
        upload = release['upload_url'].split('{', 1)[0] + '?' + urllib.parse.urlencode({'name': name})
        result = request(upload, 'POST', payload=path.read_bytes())
        if result['size'] != path.stat().st_size:
            raise ValueError('Uploaded installer size mismatch')
        if result.get('digest') and result['digest'] != 'sha256:' + digest(path):
            raise ValueError('Uploaded installer checksum mismatch')
    release = request(api + '/releases/' + str(release['id']), 'PATCH', {'draft': False, 'make_latest': 'true'})
    print('Verified installers published:', release['html_url'])


if __name__ == '__main__':
    main()
