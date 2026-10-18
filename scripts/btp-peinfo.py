#!/usr/bin/env python3
"""Lê um executável Windows (PE) e descreve o que o BTP precisa saber dele.

Uso:
  btp-peinfo.py JOGO.exe                 -> JSON com arquitetura, DLLs e renderizador sugerido
  btp-peinfo.py JOGO.exe --icon saida.ico -> também extrai o ícone principal do .exe
"""
import json
import hashlib
import importlib.util
from pathlib import Path
import re
import struct
import sys
import time

RT_ICON = 3
RT_GROUP_ICON = 14

# Helpers run with Python -I: load only the trusted sibling shipped in BTP,
# never a module from the user's game folder or PYTHONPATH.
_spec = importlib.util.spec_from_file_location('btp_rules', Path(__file__).with_name('btp-rules.py'))
_rules = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_rules)


class PE:
    def __init__(self, data):
        self.data = data
        if data[:2] != b"MZ":
            raise ValueError("não é um executável Windows (sem cabeçalho MZ)")
        pe_off = struct.unpack_from("<I", data, 0x3C)[0]
        if data[pe_off:pe_off + 4] != b"PE\0\0":
            raise ValueError("cabeçalho PE ausente")
        self.machine, nsect, self.timestamp = struct.unpack_from("<HHI", data, pe_off + 4)
        opt_size = struct.unpack_from("<H", data, pe_off + 20)[0]
        opt = pe_off + 24
        magic = struct.unpack_from("<H", data, opt)[0]
        self.is64 = magic == 0x20B
        self.subsystem = struct.unpack_from("<H", data, opt + 68)[0]
        dd = opt + (112 if self.is64 else 96)
        ndd = struct.unpack_from("<I", data, dd - 4)[0]
        self.dirs = [struct.unpack_from("<II", data, dd + 8 * i) for i in range(min(ndd, 16))]
        self.sections = []
        s = opt + opt_size
        for i in range(nsect):
            vsize, va, rsize, raw = struct.unpack_from("<IIII", data, s + 40 * i + 8)
            self.sections.append((va, max(vsize, rsize), raw, rsize))

    def off(self, rva):
        for va, size, raw, rsize in self.sections:
            if va <= rva < va + size:
                return raw + (rva - va)
        return None

    def cstr(self, rva):
        o = self.off(rva)
        if o is None:
            return ""
        end = self.data.find(b"\0", o)
        return self.data[o:end].decode("latin-1")

    def imports(self):
        names = []
        if len(self.dirs) < 2 or not self.dirs[1][0]:
            return names
        o = self.off(self.dirs[1][0])
        while o is not None and o + 20 <= len(self.data):
            name_rva = struct.unpack_from("<I", self.data, o + 12)[0]
            if not name_rva:
                break
            names.append(self.cstr(name_rva).lower())
            o += 20
        return names

    def _res_dir(self, o, base):
        n_named, n_id = struct.unpack_from("<HH", self.data, o + 12)
        for i in range(n_named + n_id):
            name, target = struct.unpack_from("<II", self.data, o + 16 + 8 * i)
            yield (None if name & 0x80000000 else name), target

    def resources(self, rtype):
        """Devolve {id: bytes} de todos os recursos de um tipo (primeiro idioma)."""
        out = {}
        if len(self.dirs) < 3 or not self.dirs[2][0]:
            return out
        base = self.off(self.dirs[2][0])
        if base is None:
            return out
        for tid, t in self._res_dir(base, base):
            if tid != rtype or not t & 0x80000000:
                continue
            for rid, r in self._res_dir(base + (t & 0x7FFFFFFF), base):
                key = rid if rid is not None else len(out) + 100000
                node = r
                while node & 0x80000000:
                    first = next(self._res_dir(base + (node & 0x7FFFFFFF), base), None)
                    if first is None:
                        break
                    node = first[1]
                if node & 0x80000000:
                    continue
                rva, size = struct.unpack_from("<II", self.data, base + node)
                o = self.off(rva)
                if o is not None:
                    out[key] = self.data[o:o + size]
        return out

    def icon(self):
        groups = self.resources(RT_GROUP_ICON)
        if not groups:
            return None
        icons = self.resources(RT_ICON)
        grp = groups[sorted(groups)[0]]
        count = struct.unpack_from("<H", grp, 4)[0]
        entries = []
        for i in range(count):
            w, h, colors, _, planes, bpp, _, iid = struct.unpack_from("<BBBBHHIH", grp, 6 + 14 * i)
            img = icons.get(iid)
            if img:
                entries.append((w, h, colors, planes, bpp, img))
        if not entries:
            return None
        header = struct.pack("<HHH", 0, 1, len(entries))
        offset = 6 + 16 * len(entries)
        table, blobs = b"", b""
        for w, h, colors, planes, bpp, img in entries:
            table += struct.pack("<BBBBHHII", w, h, colors, 0, planes, bpp, len(img), offset + len(blobs))
            blobs += img
        return header + table + blobs


def pick_renderer(arch, imports, strings):
    """Escolhe o backend pela base de regras versionada do BTP."""
    return _rules.evaluate(arch, 0, imports, strings)['renderer']


def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    path = sys.argv[1]
    data = open(path, "rb").read()
    pe = PE(data)
    arch = {0x14C: "i386", 0x8664: "x64", 0xAA64: "arm64"}.get(pe.machine, hex(pe.machine))
    imports = pe.imports()
    strings = set(m.lower() for m in re.findall(rb"[A-Za-z0-9_]{3,16}\.dll", data))
    # Ano de compilação do .exe (cabeçalho COFF). Valores fora de 1995–2035 são lixo
    # de compiladores que gravam hash no lugar da data; nesse caso fica 0.
    year = time.gmtime(pe.timestamp).tm_year if pe.timestamp else 0
    year = year if 1995 <= year <= 2035 else 0
    compatibility = _rules.evaluate(arch, year, imports, strings)
    info = {
        "arch": arch,
        "year": year,
        "gui": pe.subsystem == 2,
        "imports": imports,
        "renderer": compatibility['renderer'],
        "compatibility": compatibility,
        "executable_sha256": hashlib.sha256(data).hexdigest(),
        "icon": False,
    }
    if "--icon" in sys.argv:
        ico = pe.icon()
        if ico:
            open(sys.argv[sys.argv.index("--icon") + 1], "wb").write(ico)
            info["icon"] = True
    print(json.dumps(info))


if __name__ == "__main__":
    main()
