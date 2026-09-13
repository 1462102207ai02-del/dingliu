#!/usr/bin/env python3
"""Verify LC_CODE_SIGNATURE sanity of a Mach-O dylib (offset/size within file).
Exits non-zero on bad signature. Usage: verify_sig.py <path> [<path>...]"""
import struct
import sys

ok = True
for p in sys.argv[1:]:
    with open(p, "rb") as f:
        d = f.read()
    if len(d) < 40 or struct.unpack_from("<I", d, 0)[0] != 0xFEEDFACF:
        print(f"FAIL {p}: not a 64-bit Mach-O")
        ok = False
        continue
    ncmds, = struct.unpack_from("<I", d, 16)
    off = 32
    found = False
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", d, off)
        if cmd == 0x1B:  # LC_CODE_SIGNATURE
            dataoff, datasize = struct.unpack_from("<II", d, off + 8)
            if datasize > 0 and dataoff + datasize <= len(d):
                print(f"OK   {p}: signature off={dataoff} size={datasize} file={len(d)}")
            else:
                print(f"FAIL {p}: bad signature off={dataoff} size={datasize} file={len(d)}")
                ok = False
            found = True
            break
        if size == 0:
            print(f"FAIL {p}: zero-size load command at {off} (desync)")
            ok = False
            break
        off += size
    if not found and ok and off <= len(d):
        print(f"FAIL {p}: no LC_CODE_SIGNATURE")
        ok = False

sys.exit(0 if ok else 1)
