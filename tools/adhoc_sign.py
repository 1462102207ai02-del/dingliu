#!/usr/bin/env python3
"""Self-contained ad-hoc code signer for 64-bit Mach-O dylibs.

Fixes files whose LC_CODE_SIGNATURE is corrupt (garbage offsets - common in
TrollFools-style tweak dylibs), by:
  1. stripping the corrupt LC_CODE_SIGNATURE load command
  2. truncating any trailing orphan signature blob
  3. inserting a fresh LC_CODE_SIGNATURE
  4. building a valid ad-hoc SuperBlob (CodeDirectory v0x20400, SHA-256,
     Requirements set) and appending it
  5. fixing __LINKEDIT filesize/vmsize

Usage: adhoc_sign.py <identifier> <path>
"""
import hashlib
import struct
import sys

CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0
CSMAGIC_CODEDIRECTORY = 0xFADE0C02
CSMAGIC_REQUIREMENTS = 0xFADE0C01
CSMAGIC_REQUIREMENT = 0xFADE0C00

CSSLOT_CODEDIRECTORY = 0
CSSLOT_REQUIREMENTS = 2

CS_ADHOC = 0x00000002

PAGE_SHIFT = 12
PAGE_SIZE = 1 << PAGE_SHIFT


def align(x, a):
    return (x + a - 1) & ~(a - 1)


def blob(magic, payload):
    return struct.pack(">II", magic, 8 + len(payload)) + payload


def main():
    ident, p = sys.argv[1], sys.argv[2]
    with open(p, "rb") as f:
        d = bytearray(f.read())
    orig_len = len(d)

    if struct.unpack_from("<I", d, 0)[0] != 0xFEEDFACF:
        print(f"FAIL {p}: not a 64-bit Mach-O")
        sys.exit(1)

    ncmds, = struct.unpack_from("<I", d, 16)
    sizeofcmds, = struct.unpack_from("<I", d, 20)

    # ---- pass 1: locate commands, segments, linkedit data extents ----------
    off = 32
    symtab = None
    sig_lc_off = None
    sig_data = None
    linkedit = None
    max_end = 0  # last real byte of linkedit content
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", d, off)
        if cmd == 0x1B:  # LC_CODE_SIGNATURE
            sig_lc_off = off
            sig_data = struct.unpack_from("<II", d, off + 8)
        elif cmd == 0x19:  # LC_SEGMENT_64
            name = d[off + 8:off + 24].split(b"\x00")[0].decode()
            vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", d, off + 24)
            if name == "__LINKEDIT":
                linkedit = (off, fileoff, filesize)
        elif cmd == 0x02:  # LC_SYMTAB
            symtab = struct.unpack_from("<IIII", d, off + 8)  # symoff nsyms stroff strsize
        elif cmd in (0x22, 0x80000022):  # dyld_info
            doff, dsz = struct.unpack_from("<II", d, off + 8)
            max_end = max(max_end, doff + dsz)
        elif cmd in (0x26, 0x2A, 0x2B, 0x2C, 0x2E, 0x80000034):  # linkedit_data cmds
            doff, dsz = struct.unpack_from("<II", d, off + 8)
            if cmd != 0x1B and dsz:
                max_end = max(max_end, doff + dsz)
        off += size

    if symtab:
        symoff, nsyms, stroff, strsize = symtab
        max_end = max(max_end, symoff + nsyms * 16, stroff + strsize)
    if linkedit:
        max_end = max(max_end, linkedit[1])

    # ---- step 1: strip corrupt signature LC --------------------------------
    if sig_lc_off is not None:
        del d[sig_lc_off:sig_lc_off + 24]
        struct.pack_into("<I", d, 16, ncmds - 1)
        struct.pack_into("<I", d, 20, sizeofcmds - 24)
        ncmds -= 1
        sizeofcmds -= 24
        end = 32 + sizeofcmds
        d[end:end + 24] = b"\x00" * 24
        print(f"stripped corrupt LC_CODE_SIGNATURE {sig_data}")

    # ---- step 2: truncate orphan blob garbage ------------------------------
    if orig_len > max_end:
        del d[max_end:]
        if linkedit:
            le_off, le_fileoff, le_filesize = linkedit
            newsize = max_end - le_fileoff
            struct.pack_into("<QQ", d, le_off + 32 + 8, newsize, align(newsize, PAGE_SIZE))
        print(f"truncated orphan trailing data: {orig_len} -> {max_end}")

    clean_end = align(len(d), 16)

    # ---- step 3: insert fresh LC_CODE_SIGNATURE ----------------------------
    # ensure there is zero padding after load commands to absorb 16 bytes
    hdr_end = 32 + sizeofcmds
    # find first section file content start = min non-zero byte after hdr_end
    probe = d[hdr_end:clean_end]
    nz = next((i for i, b in enumerate(probe) if b != 0), len(probe))
    if nz < 16:
        print(f"FAIL {p}: no room in load-command padding ({nz} bytes)")
        sys.exit(1)
    lc = struct.pack("<IIII", 0x1B, 16, 0, 0)  # dataoff/datasize patched later
    d[hdr_end:hdr_end + 16] = lc
    struct.pack_into("<I", d, 16, ncmds + 1)
    struct.pack_into("<I", d, 20, sizeofcmds + 16)
    ncmds += 1
    sizeofcmds += 16

    # ---- step 4: build ad-hoc SuperBlob ------------------------------------
    # requirements: empty requirements set (count=0) - content is only hashed,
    # never evaluated for ad-hoc code
    req = blob(CSMAGIC_REQUIREMENTS, struct.pack(">I", 0))

    # code directory
    ident_b = ident.encode() + b"\x00"
    cd_hdr_len = 88  # v0x20400
    n_special = CSSLOT_REQUIREMENTS  # => slots -1 (info, empty) .. -2 (requirements)
    n_code = (clean_end + PAGE_SIZE - 1) // PAGE_SIZE

    cd_len = cd_hdr_len + len(ident_b) + (n_special + n_code) * 32
    cd = bytearray(cd_hdr_len + len(ident_b))
    struct.pack_into(">III", cd, 0, CSMAGIC_CODEDIRECTORY, 8 + cd_len - 8, 0x20400)
    struct.pack_into(">I", cd, 12, CS_ADHOC)
    ident_off = cd_hdr_len
    hash_off = ident_off + len(ident_b) + (n_special * 32)
    struct.pack_into(">I", cd, 16, hash_off)
    struct.pack_into(">I", cd, 20, ident_off)
    struct.pack_into(">I", cd, 24, n_special)
    struct.pack_into(">I", cd, 28, n_code)
    struct.pack_into(">I", cd, 32, clean_end)  # codeLimit
    cd[36] = 32   # hashSize sha256
    cd[37] = 2    # hashType sha256
    cd[38] = 0    # platform
    cd[39] = PAGE_SHIFT
    cd[ident_off:ident_off + len(ident_b)] = ident_b

    # special slots: -1 info(empty), -2 requirements
    special = [hashlib.sha256(b"").digest(), hashlib.sha256(req).digest()]
    hashes = b"".join(special)  # -1 then -2
    # code slots
    for i in range(n_code):
        chunk = d[i * PAGE_SIZE:(i + 1) * PAGE_SIZE]
        hashes += hashlib.sha256(chunk).digest()
    cd[hash_off:] = hashes
    cd_blob = bytes(cd)

    # superblob
    body = struct.pack(">I", 2)                       # count
    body += struct.pack(">II", CSSLOT_CODEDIRECTORY, 8 + 4 + 4 + 8)  # placeholder, fixed below
    # layout: superblob header (12) + 2 indices (8 each) + cd + req
    cd_off = 12 + 16
    req_off = cd_off + len(cd_blob)
    total = req_off + len(req)
    sb = struct.pack(">III", CSMAGIC_EMBEDDED_SIGNATURE, total, 2)
    sb += struct.pack(">II", CSSLOT_CODEDIRECTORY, cd_off)
    sb += struct.pack(">II", CSSLOT_REQUIREMENTS, req_off)
    sb += cd_blob + req
    assert len(sb) == total

    blob_len = len(sb)
    dataoff = clean_end
    # patch LC
    # find inserted LC: it is at 32 + (sizeofcmds - 16)
    lc_pos = 32 + sizeofcmds - 16
    struct.pack_into("<II", d, lc_pos + 8, dataoff, blob_len)

    # ---- step 5: append blob + fix __LINKEDIT ------------------------------
    d += sb
    if linkedit:
        le_off, le_fileoff, _ = linkedit
        newsize = dataoff + blob_len - le_fileoff
        struct.pack_into("<QQ", d, le_off + 32 + 8, newsize, align(newsize, PAGE_SIZE))

    with open(p, "wb") as f:
        f.write(d)
    print(f"OK   {p}: adhoc signed, identifier={ident}, dataoff={dataoff}, blob={blob_len}, file={len(d)}")


if __name__ == "__main__":
    main()
