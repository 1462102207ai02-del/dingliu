#!/usr/bin/env python3
"""Diagnose Mach-O load commands / code signature layout."""
import struct, sys

LC_NAMES = {
    0x19: "LC_SEGMENT_64", 0x1B: "LC_UUID", 0x02: "LC_SYMTAB",
    0x0B: "LC_DYSYMTAB", 0x0C: "LC_LOAD_DYLIB", 0x0D: "LC_ID_DYLIB",
    0x1C: "LC_SEGMENT_SPLIT_INFO", 0x1D: "LC_CODE_SIGNATURE",
    0x20: "LC_LAZY_LOAD_DYLIB", 0x22: "LC_DYLD_INFO",
    0x80000022: "LC_DYLD_INFO_ONLY", 0x24: "LC_VERSION_MIN_MACOSX",
    0x25: "LC_VERSION_MIN_IPHONEOS", 0x26: "LC_FUNCTION_STARTS", 0x29: "LC_DATA_IN_CODE",
    0x2A: "LC_SOURCE_VERSION", 0x2B: "LC_DYLIB_CODE_SIGN_DRS",
    0x2C: "LC_ENCRYPTION_INFO_64", 0x2E: "LC_LINKER_OPTION",
    0x32: "LC_BUILD_VERSION", 0x33: "LC_DYLD_EXPORTS_TRIE",
    0x80000033: "LC_DYLD_EXPORTS_TRIE", 0x80000034: "LC_DYLD_CHAINED_FIXUPS",
    0x1E: "LC_SEGMENT_SPLIT_INFO", 0x0E: "LC_LOAD_WEAK_DYLIB", 0x18: "LC_RPATH",
}


def main(path):
    with open(path, "rb") as f:
        d = f.read()
    print(f"file: {path}\nsize: {len(d)} (0x{len(d):x})")
    magic, = struct.unpack_from("<I", d, 0)
    print(f"magic: 0x{magic:x}", end="  ")
    if magic == 0xFEEDFACF:
        print("(MH_MAGIC_64)")
    elif magic == 0xCAFEBABE:
        print("(FAT) -> need slice check")
    else:
        print("(??)")
        return
    cputype, = struct.unpack_from("<i", d, 4)
    filetype, = struct.unpack_from("<I", d, 12)
    ncmds, = struct.unpack_from("<I", d, 16)
    sizeofcmds, = struct.unpack_from("<I", d, 20)
    flags, = struct.unpack_from("<I", d, 24)
    print(f"cputype=0x{cputype:x} filetype={filetype} ncmds={ncmds} sizeofcmds={sizeofcmds} flags=0x{flags:x}")

    off = 32
    segs = {}
    sig = None
    for i in range(ncmds):
        cmd, size = struct.unpack_from("<II", d, off)
        name = LC_NAMES.get(cmd, hex(cmd))
        extra = ""
        if cmd == 0x19:
            seg = d[off + 8:off + 24].split(b"\x00")[0].decode()
            vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", d, off + 24)
            segs[seg] = (fileoff, filesize, vmaddr, vmsize)
            extra = f"{seg:12s} fileoff=0x{fileoff:x} filesize=0x{filesize:x} vmaddr=0x{vmaddr:x} vmsize=0x{vmsize:x} end=0x{fileoff+filesize:x}"
        elif cmd == 0x1D:
            dataoff, datasize = struct.unpack_from("<II", d, off + 8)
            sig = (dataoff, datasize)
            extra = f"dataoff=0x{dataoff:x} datasize=0x{datasize:x} end=0x{dataoff+datasize:x}"
        elif cmd == 0x1B:
            extra = f"uuid={d[off+8:off+24].hex()}"
        print(f"  [{i:2d}] off=0x{off:04x} size={size:3d} {name} {extra}")
        off += size

    print(f"\nload commands end at 0x{32+sizeofcmds:x}, file size 0x{len(d):x}")
    if "__LINKEDIT" in segs:
        lfo, lfs, _, _ = segs["__LINKEDIT"]
        print(f"__LINKEDIT: fileoff=0x{lfo:x} filesize=0x{lfs:x} -> end=0x{lfo+lfs:x}")
        print(f"__LINKEDIT end vs file size: {'OK' if lfo+lfs <= len(d) else 'OVERRUN!'}")
    else:
        print("__LINKEDIT: MISSING")

    if sig is None:
        print("\nLC_CODE_SIGNATURE: ABSENT  <== ct_bypass says 'no code signature found'")
        return
    dataoff, datasize = sig
    ok1 = dataoff + datasize <= len(d)
    print(f"\nLC_CODE_SIGNATURE: dataoff=0x{dataoff:x} datasize=0x{datasize:x}")
    print(f"  within file: {'YES' if ok1 else 'NO  <== CORRUPT/OVERRUN'}")
    if "__LINKEDIT" in segs:
        lfo, lfs, _, _ = segs["__LINKEDIT"]
        ok2 = dataoff >= lfo and dataoff + datasize <= lfo + lfs
        print(f"  within __LINKEDIT: {'YES' if ok2 else 'NO  <== signature outside __LINKEDIT (dyld/ChOma reject)'}")
    if ok1:
        smagic, slen = struct.unpack_from(">II", d, dataoff)
        print(f"  superblob magic=0x{smagic:x} (expect 0xfade0cc0) length={slen} (expect {datasize})")
        if smagic == 0xFADE0CC0 and slen == datasize:
            count, = struct.unpack_from(">I", d, dataoff + 8)
            print(f"  count={count}")
            for i in range(count):
                st, so = struct.unpack_from(">II", d, dataoff + 12 + i * 8)
                bm, bl = struct.unpack_from(">II", d, dataoff + so)
                print(f"    slot={st} off={so} magic=0x{bm:x} len={bl}")
                if bm == 0xFADE0C02:
                    ver, = struct.unpack_from(">I", d, dataoff + so + 8)
                    print(f"      CodeDirectory version=0x{ver:x}")


if __name__ == "__main__":
    main(sys.argv[1])
