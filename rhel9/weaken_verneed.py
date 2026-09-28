#!/usr/bin/env python3
"""Mark a GLIBC version requirement as weak (VER_FLG_WEAK) in an ELF64 LE file.

glibc's loader treats a missing *weak* version requirement as non-fatal, so a
library built on glibc 2.35 that only needs e.g. hypot@GLIBC_2.35 loads on 2.34
once the symbol's own version is cleared (patchelf --clear-symbol-version).

usage: weaken_verneed.py FILE [VERSION]   (default VERSION: GLIBC_2.35)
"""
import struct
import sys

VER_FLG_WEAK = 0x2


def main(path, version="GLIBC_2.35"):
    with open(path, "r+b") as f:
        data = bytearray(f.read())
        assert data[:4] == b"\x7fELF" and data[4] == 2 and data[5] == 1, "ELF64 LE only"
        e_shoff, = struct.unpack_from("<Q", data, 0x28)
        e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", data, 0x3A)

        def shdr(i):
            return struct.unpack_from("<IIQQQQIIQQ", data, e_shoff + i * e_shentsize)

        SHT_GNU_verneed = 0x6FFFFFFE
        patched = 0
        for i in range(e_shnum):
            _, sh_type, _, _, sh_offset, _, sh_link, sh_info, _, _ = shdr(i)
            if sh_type != SHT_GNU_verneed:
                continue
            strtab_off = shdr(sh_link)[4]

            def cstr(off):
                end = data.index(b"\0", strtab_off + off)
                return data[strtab_off + off:end].decode()

            vn = sh_offset
            for _ in range(sh_info):
                _, vn_cnt, vn_file, vn_aux, vn_next = struct.unpack_from("<HHIII", data, vn)
                va = vn + vn_aux
                for _ in range(vn_cnt):
                    _, vna_flags, _, vna_name, vna_next = struct.unpack_from("<IHHII", data, va)
                    if cstr(vna_name) == version:
                        struct.pack_into("<H", data, va + 4, vna_flags | VER_FLG_WEAK)
                        print(f"{path}: {cstr(vn_file)} {version} flags {vna_flags:#x} -> {vna_flags | VER_FLG_WEAK:#x}")
                        patched += 1
                    va += vna_next
                vn += vn_next
        if not patched:
            sys.exit(f"{path}: no {version} requirement found")
        f.seek(0)
        f.write(data)


if __name__ == "__main__":
    main(*sys.argv[1:])
