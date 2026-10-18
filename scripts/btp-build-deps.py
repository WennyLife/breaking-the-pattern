#!/usr/bin/env python3
"""Obtém o Sparkle fixado para compilar/publicar o BTP; não é usado pelo jogador."""
import importlib.util
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location('btp_runtime', Path(__file__).with_name('btp-runtime.py'))
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)
component = {
    'version': 'Sparkle 2.10.0',
    'url': 'https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz',
    'size': 16319840,
    'sha256': 'c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c',
    'unpacked_limit': 120000000,
}
runtime.extract(runtime.download(component), Path(sys.argv[1]), component['unpacked_limit'])
