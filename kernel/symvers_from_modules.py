#!/usr/bin/env python3
"""Rebuild a Module.symvers for the shipped kernel from its module tree, so one extra module can be built later
(kernel/isa_emu_patch/build_extra_module.sh) without rebuilding the whole kernel, yet with the exact symbol CRCs
the running kernel checks (CONFIG_MODVERSIONS).

  - every module's exports: names from __ksymtab (+ __ksymtab_strings), CRCs from __kcrctab, owner = that module
  - every module's imports: __versions entries ({u64 crc; char name[56]}); symbols nobody in the tree exports are
    the kernel's own (owner vmlinux)

Usage: symvers_from_modules.py <lib/modules/VERSION dir> <Module.symvers out>
"""
import os
import struct
import sys


def sections(data):
    shoff, = struct.unpack_from('<Q', data, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from('<HHH', data, 0x3a)
    hdrs = [struct.unpack_from('<IIQQQQIIQQ', data, shoff + i * shentsize) for i in range(shnum)]
    strtab = hdrs[shstrndx]
    def name(off):
        start = strtab[4] + off
        return data[start:data.index(b'\0', start)].decode()
    return {name(h[0]): h for h in hdrs}, hdrs


def cstr(data, off):
    return data[off:data.index(b'\0', off)].decode()


def read_module(path):
    data = open(path, 'rb').read()
    if data[:4] != b'\x7fELF':
        return [], []
    secs, hdrs = sections(data)
    exports, imports = [], []
    if '__ksymtab' in secs and '__kcrctab' in secs and '.symtab' in secs:
        ksym, kcrc, symtab = secs['__ksymtab'], secs['__kcrctab'], secs['.symtab']
        ksym_index = hdrs.index(ksym)
        strtab = hdrs[symtab[6]]
        for i in range(symtab[5] // 24):
            st_name, st_info, st_other, st_shndx, st_value, st_size = struct.unpack_from('<IBBHQQ', data, symtab[4] + i * 24)
            if st_shndx != ksym_index:
                continue
            sym = cstr(data, strtab[4] + st_name)
            if not sym.startswith('__ksymtab_'):
                continue
            idx = st_value // 12		# struct kernel_symbol: three relative int offsets
            crc, = struct.unpack_from('<I', data, kcrc[4] + idx * 4)
            exports.append((sym[len('__ksymtab_'):], crc))
    if '__versions' in secs:
        v = secs['__versions']
        for off in range(v[4], v[4] + v[5], 64):
            crc, = struct.unpack_from('<Q', data, off)
            imports.append((cstr(data, off + 8), crc & 0xffffffff))
    return exports, imports


def main():
    root, out = sys.argv[1], sys.argv[2]
    owner, crcs, conflicts = {}, {}, 0
    for dirpath, _, files in os.walk(os.path.join(root, 'kernel')):
        for f in files:
            if not f.endswith('.ko'):
                continue
            path = os.path.join(dirpath, f)
            mod = os.path.relpath(path, root)[len('kernel/'):-len('.ko')]
            exports, imports = read_module(path)
            for name, crc in exports:
                owner[name] = mod
                if crcs.setdefault(name, crc) != crc:
                    conflicts += 1
            for name, crc in imports:
                if crcs.setdefault(name, crc) != crc:
                    conflicts += 1
    if conflicts:
        sys.exit(f'{conflicts} symbols with two different CRCs: the tree is not from one kernel build')
    with open(out, 'w') as fh:
        for name in sorted(crcs):
            fh.write(f'0x{crcs[name]:08x}\t{name}\t{owner.get(name, "vmlinux")}\tEXPORT_SYMBOL_GPL\t\n')
    print(f'{len(crcs)} symbols ({len(owner)} exported by modules) -> {out}')


main()
