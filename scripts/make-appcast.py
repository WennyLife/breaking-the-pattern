#!/usr/bin/env python3
"""Gera o feed de atualização a partir de um ZIP BTP já verificado, usando a chave no Keychain."""
import argparse
from datetime import datetime, timezone
from email.utils import format_datetime
from pathlib import Path
import plistlib
import subprocess
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--archive', type=Path, required=True)
parser.add_argument('--sign-tool', type=Path, required=True)
parser.add_argument('--output', type=Path, default=Path('updates/appcast.xml'))
args = parser.parse_args()
info = plistlib.loads((args.app / 'Contents/Info.plist').read_bytes())
subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(args.app)], check=True)
signature = subprocess.check_output([str(args.sign_tool), '--account', 'org.lendaii.btp.updates', '-p', str(args.archive)], text=True).strip()
subprocess.run([str(args.sign_tool), '--account', 'org.lendaii.btp.updates', '--verify', str(args.archive), signature], check=True)
ns = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', ns)
rss = ET.Element('rss', {'version': '2.0'})
channel = ET.SubElement(rss, 'channel')
ET.SubElement(channel, 'title').text = 'Breaking the Pattern Updates'
ET.SubElement(channel, 'link').text = 'https://github.com/WennyLife/breaking-the-pattern/releases'
item = ET.SubElement(channel, 'item')
version = info['CFBundleShortVersionString']
ET.SubElement(item, 'title').text = 'BTP ' + version
ET.SubElement(item, 'pubDate').text = format_datetime(datetime.now(timezone.utc))
ET.SubElement(item, '{' + ns + '}version').text = info['CFBundleVersion']
ET.SubElement(item, '{' + ns + '}shortVersionString').text = version
ET.SubElement(item, '{' + ns + '}minimumSystemVersion').text = info['LSMinimumSystemVersion']
ET.SubElement(item, 'description').text = ('English: Automatic required components and tested NFSU2/GTA recipes. In-app signed updates, English/Portuguese interface, independent compatibility runtime, '
    'edition-specific NFS Underground 2 and GTA San Andreas recipes. No games included. '
    'Português: atualizações assinadas pelo app, interface em inglês/português, motor independente e receitas por edição para NFSU2/GTA SA. Sem jogos incluídos. '
    'Splinter Cell remains experimental and is not part of this initial release.')
ET.SubElement(item, 'enclosure', {'url': f'https://github.com/WennyLife/breaking-the-pattern/releases/download/v{version}/{args.archive.name}',
    'length': str(args.archive.stat().st_size), 'type': 'application/octet-stream', '{' + ns + '}edSignature': signature})
args.output.parent.mkdir(parents=True, exist_ok=True)
ET.indent(rss)
ET.ElementTree(rss).write(args.output, encoding='utf-8', xml_declaration=True)
print('Appcast assinado pelo pacote verificado:', args.output)
