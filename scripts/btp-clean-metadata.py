#!/usr/bin/env python3
"""Remove metadados Finder incompatíveis com assinatura somente do staging."""
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
for attr in ('com.apple.FinderInfo', 'com.apple.ResourceFork'):
    subprocess.run(['/usr/bin/xattr', '-r', '-d', attr, str(root)], capture_output=True)
    # Algumas pastas sincronizadas reaplicam FinderInfo em pacotes enquanto o
    # percurso recursivo ocorre. Limpar seus diretórios ao final também evita
    # que um link do framework interrompa o percurso antes de chegar à raiz.
    bundles = [p for p in root.rglob('*') if not p.is_symlink() and p.is_dir()
               and p.suffix in ('.app', '.framework', '.xpc')]
    for path in sorted(bundles, key=lambda p: len(p.parts), reverse=True) + [root]:
        subprocess.run(['/usr/bin/xattr', '-d', attr, str(path)], capture_output=True)
