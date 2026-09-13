#!/usr/bin/env python3
"""Ad-hoc code signer for 64-bit Mach-O dylibs (v3).

Why this exists
---------------
Theos on Linux emits a dylib whose LC_CODE_SIGNATURE is garbage, and
`ldid` often only appends a blob without rewriting the load command.
TrollFools' `ct_bypass` (ChOma) then rejects the file with
"no code signature found".

v1: patched __LINKEDIT at lc+40 (fileoff, not filesize) and deleted a
    16-byte linkedit_data_command as if it were 24 bytes.
v2: still used LC_CODE_SIGNATURE = 0x1B. That constant is LC_UUID
    (24 bytes). The signer wrote SuperBlob offsets into the UUID
    command and left the real 0x1D pointing at a stale Theos blob
    whose datasize ran past EOF. ChOma only reads 0x1D, so injection
    failed while verify_sig.py (also using 0x1B) reported OK.
v3: LC_CODE_SIGNATURE = 0x1D, cmdsize forced to 16, hashOffset points
    at the first *code* hash (Apple layout), special slots sit just
    before it.

Layout of LC_SEGMENT_64:
    +0  cmd       +4  cmdsize    +8  segname[16]
    +24 vmaddr    +32 vmsize     +40 fileoff    +48 filesize

Usage: adhoc_sign.py <path> [identifier]
"""
import hashlib
import os
import struct
import sys

CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0
CSMAGIC_CODEDIRECTORY = 0xFADE0C02
CSMAGIC_REQUIREMENTS = 0xFADE0C01

CSSLOT_CODEDIRECTORY = 0
CSSLOT_REQUIREMENTS = 2

CS_ADHOC = 0x00000002

PAGE_SHIFT = 12
PAGE_SIZE = 1 << PAGE_SHIFT

LC_SEGMENT_64 = 0x19
LC_ID_DYLIB = 0x0D
LC_UUID = 0x1B
LC_CODE_SIGNATURE = 0x1D          # NOT 0x1B (that is LC_UUID)
LC_SYMTAB = 0x02
LC_DYLD_INFO = 0x22
LC_DYLD_INFO_ONLY = 0x80000022
# linkedit_data_command: cmd, cmdsize, dataoff, datasize (16 bytes)
LINKEDIT_DATA_CMDS = (
    0x1D,          # LC_CODE_SIGNATURE
    0x1E,          # LC_SEGMENT_SPLIT_INFO
    0x26,          # LC_FUNCTION_STARTS
    0x29,          # LC_DATA_IN_CODE
    0x2B,          # LC_DYLIB_CODE_SIGN_DRS
    0x2E,          # LC_LINKER_OPTIMIZATION_HINT
    0x80000033,    # LC_DYLD_EXPORTS_TRIE
    0x80000034,    # LC_DYLD_CHAINED_FIXUPS
)


def align(x, a):
    return (x + a - 1) & ~(a - 1)


def blob(magic, payload):
    return struct.pack(">II", magic, 8 + len(payload)) + payload


class MachO(object):
    def __init__(self, d):
        self.d = bytearray(d)
        if struct.unpack_from("<I", self.d, 0)[0] != 0xFEEDFACF:
            raise SystemExit("FAIL: not a 64-bit Mach-O")
        self.ncmds, = struct.unpack_from("<I", self.d, 16)
        self.sizeofcmds, = struct.unpack_from("<I", self.d, 20)
        self.scan()

    def scan(self):
        d = self.d
        self.segs = {}
        self.sig_lc = None
        self.sig = None
        self.uuid_lc = None
        self.symtab = None
        self.ident = None
        off = 32
        for _ in range(self.ncmds):
            cmd, size = struct.unpack_from("<II", d, off)
            if size < 8:
                raise SystemExit(f"FAIL: cmdsize {size} at 0x{off:x}")
            if cmd == LC_SEGMENT_64:
                name = d[off + 8:off + 24].split(b"\x00")[0].decode()
                vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", d, off + 24)
                self.segs[name] = [off, vmaddr, vmsize, fileoff, filesize]
            elif cmd == LC_CODE_SIGNATURE:
                self.sig_lc = off
                self.sig = struct.unpack_from("<II", d, off + 8)
            elif cmd == LC_UUID:
                self.uuid_lc = off
            elif cmd == LC_SYMTAB:
                self.symtab = struct.unpack_from("<IIII", d, off + 8)
            elif cmd == LC_ID_DYLIB:
                name_off, = struct.unpack_from("<I", d, off + 8)
                self.ident = d[off + name_off:off + size].split(b"\x00")[0].decode()
            off += size

    def linkedit_tail(self):
        """Last byte of real __LINKEDIT content (signature may start here)."""
        d = self.d
        end = 0
        off = 32
        for _ in range(self.ncmds):
            cmd, size = struct.unpack_from("<II", d, off)
            if cmd in (LC_DYLD_INFO, LC_DYLD_INFO_ONLY):
                doff, dsz = struct.unpack_from("<II", d, off + 8)
                end = max(end, doff + dsz)
            elif cmd in LINKEDIT_DATA_CMDS and cmd != LC_CODE_SIGNATURE:
                doff, dsz = struct.unpack_from("<II", d, off + 8)
                if dsz:
                    end = max(end, doff + dsz)
            off += size
        if self.symtab:
            symoff, nsyms, stroff, strsize = self.symtab
            end = max(end, symoff + nsyms * 16, stroff + strsize)
        if "__LINKEDIT" in self.segs:
            end = max(end, self.segs["__LINKEDIT"][3])
        return end

    def repair_linkedit(self):
        if "__LINKEDIT" not in self.segs:
            return
        lc, vmaddr, _vmsize, fileoff, _filesize = self.segs["__LINKEDIT"]
        slides = [s[1] - s[3] for n, s in self.segs.items() if n != "__LINKEDIT"]
        slide = min(slides) if slides else 0
        want = vmaddr - slide
        if fileoff == want:
            return
        # 只在「修完仍指向文件内部」时才修。否则会把 fileoff 推到文件之外，
        # 后面算 __LINKEDIT 的 filesize 会变成负数并直接 struct.error
        # （v1.1.0 的 dylib 变大后 fileoff/vmaddr 出现间隙就踩到了）。
        if want < 0 or want > len(self.d):
            print(f"skip __LINKEDIT fileoff repair 0x{fileoff:x} -> 0x{want:x} "
                  f"(target outside file, size=0x{len(self.d):x})")
            return
        if want < fileoff:
            print(f"skip __LINKEDIT fileoff repair 0x{fileoff:x} -> 0x{want:x} (backwards)")
            return
        print(f"repair __LINKEDIT fileoff 0x{fileoff:x} -> 0x{want:x} "
              f"(vmaddr=0x{vmaddr:x}, slide=0x{slide:x})")
        struct.pack_into("<Q", self.d, lc + 40, want)
        self.segs["__LINKEDIT"][3] = want
        self.scan()

    def repair_uuid(self):
        """v2 wrote SuperBlob offsets into LC_UUID. Restore a random UUID."""
        if self.uuid_lc is None:
            return
        off = self.uuid_lc
        a, b = struct.unpack_from("<II", self.d, off + 8)
        if a < len(self.d) and 16 <= b <= 0x20000:
            self.d[off + 8:off + 24] = os.urandom(16)
            print("repaired LC_UUID clobbered by signer v2")

    def drop_orphan_blob(self, tail):
        """Drop trailing signature bytes. Never delete inside load commands."""
        if len(self.d) > tail:
            print(f"truncated orphan trailing data: {len(self.d)} -> {tail}")
            del self.d[tail:]

    def lc_slot(self):
        """Reuse existing LC_CODE_SIGNATURE (0x1D), else claim 16 pad bytes."""
        if self.sig_lc is not None:
            return self.sig_lc
        hdr_end = 32 + self.sizeofcmds
        pad = 16
        if all(b == 0 for b in self.d[hdr_end:hdr_end + pad]):
            self.d[hdr_end:hdr_end + 16] = struct.pack("<IIII", LC_CODE_SIGNATURE, 16, 0, 0)
            self.ncmds += 1
            self.sizeofcmds += 16
            struct.pack_into("<I", self.d, 16, self.ncmds)
            struct.pack_into("<I", self.d, 20, self.sizeofcmds)
            self.sig_lc = hdr_end
            print(f"inserted LC_CODE_SIGNATURE at 0x{hdr_end:x}")
            return hdr_end
        raise SystemExit("FAIL: no LC_CODE_SIGNATURE and no room to insert one")

    def sign(self, ident):
        d = self.d
        dataoff = align(len(d), 16)
        if dataoff > len(d):
            d += b"\x00" * (dataoff - len(d))

        lc_pos = self.lc_slot()

        ident_b = ident.encode() + b"\x00"
        cd_hdr_len = 88
        n_special = 2
        n_code = (dataoff + PAGE_SIZE - 1) // PAGE_SIZE
        # Apple: hashOffset = first CODE hash. Special -i is hashOffset - i*32.
        ident_off = cd_hdr_len
        special_off = ident_off + len(ident_b)
        hash_off = special_off + n_special * 32
        cd_len = hash_off + n_code * 32
        req = blob(CSMAGIC_REQUIREMENTS, struct.pack(">I", 0))
        sb_len = 12 + 16 + cd_len + len(req)

        struct.pack_into("<IIII", d, lc_pos, LC_CODE_SIGNATURE, 16, dataoff, sb_len)
        if "__LINKEDIT" in self.segs:
            lc, _vmaddr, _vmsize, fileoff, _filesize = self.segs["__LINKEDIT"]
            new_filesize = dataoff + sb_len - fileoff
            if new_filesize <= 0:
                new_filesize = sb_len
            new_vmsize = align(new_filesize, PAGE_SIZE)
            struct.pack_into("<Q", d, lc + 48, new_filesize)
            struct.pack_into("<Q", d, lc + 32, new_vmsize)
            self.segs["__LINKEDIT"][4] = new_filesize
            self.segs["__LINKEDIT"][2] = new_vmsize

        cd = bytearray(cd_len)
        struct.pack_into(">IIII", cd, 0, CSMAGIC_CODEDIRECTORY, cd_len, 0x20400, CS_ADHOC)
        struct.pack_into(">I", cd, 16, hash_off)
        struct.pack_into(">I", cd, 20, ident_off)
        struct.pack_into(">I", cd, 24, n_special)
        struct.pack_into(">I", cd, 28, n_code)
        struct.pack_into(">I", cd, 32, dataoff)
        cd[36] = 32
        cd[37] = 2
        cd[38] = 0
        cd[39] = PAGE_SHIFT
        struct.pack_into(">Q", cd, 56, dataoff)
        text = self.segs.get("__TEXT")
        if text:
            struct.pack_into(">QQQ", cd, 64, text[1], text[2], 0)
        cd[ident_off:ident_off + len(ident_b)] = ident_b

        hashes = hashlib.sha256(req).digest() + bytes(32)
        for i in range(n_code):
            chunk = bytes(d[i * PAGE_SIZE:(i + 1) * PAGE_SIZE])
            if len(chunk) < PAGE_SIZE:
                chunk += b"\x00" * (PAGE_SIZE - len(chunk))
            hashes += hashlib.sha256(chunk).digest()
        cd[special_off:special_off + len(hashes)] = hashes
        cd = bytes(cd)

        cd_off = 12 + 16
        req_off = cd_off + len(cd)
        total = req_off + len(req)
        sb = struct.pack(">III", CSMAGIC_EMBEDDED_SIGNATURE, total, 2)
        sb += struct.pack(">II", CSSLOT_CODEDIRECTORY, cd_off)
        sb += struct.pack(">II", CSSLOT_REQUIREMENTS, req_off)
        sb += cd + req
        assert len(sb) == sb_len == total

        d += sb
        self.sig = (dataoff, len(sb))
        return dataoff, len(sb)


def validate(path):
    with open(path, "rb") as f:
        d = f.read()
    m = MachO(d)
    m.scan()
    errs = []

    size = len(d)
    if m.sig is None:
        return ["LC_CODE_SIGNATURE (0x1D) missing"], None, (0, 0)
    dataoff, datasize = m.sig
    if m.sig_lc is not None:
        cmd, csz = struct.unpack_from("<II", d, m.sig_lc)
        if cmd != LC_CODE_SIGNATURE:
            errs.append(f"signature LC cmd is 0x{cmd:x}, want 0x1D")
        if csz != 16:
            errs.append(f"LC_CODE_SIGNATURE cmdsize {csz}, want 16")

    if dataoff + datasize != size:
        errs.append(f"signature does not end at EOF: {dataoff + datasize} != {size}")
    if dataoff % 16:
        errs.append(f"dataoff not 16-aligned: 0x{dataoff:x}")
    if dataoff + datasize > size:
        errs.append(f"signature overruns file: 0x{dataoff:x}+0x{datasize:x} > 0x{size:x}")
        return errs, None, (0, 0)

    le = m.segs.get("__LINKEDIT")
    if le is None:
        errs.append("__LINKEDIT missing")
    else:
        lfo, lfs = le[3], le[4]
        if not (lfo <= dataoff and dataoff + datasize <= lfo + lfs):
            errs.append(f"signature outside __LINKEDIT [0x{lfo:x},0x{lfo+lfs:x}) "
                        f"sig=[0x{dataoff:x},0x{dataoff+datasize:x})")
        if lfo + lfs != size:
            errs.append(f"__LINKEDIT does not end at EOF: 0x{lfo+lfs:x} != 0x{size:x}")

    order = sorted(m.segs.values(), key=lambda s: s[3])
    for a, b in zip(order, order[1:]):
        if a[3] + a[4] > b[3]:
            errs.append(f"segments overlap: end 0x{a[3]+a[4]:x} > next start 0x{b[3]:x}")

    magic, length = struct.unpack_from(">II", d, dataoff)
    if magic != CSMAGIC_EMBEDDED_SIGNATURE:
        errs.append(f"bad superblob magic 0x{magic:x}")
        return errs, None, (0, 0)
    if length != datasize:
        errs.append(f"superblob length {length} != datasize {datasize}")
    count, = struct.unpack_from(">I", d, dataoff + 8)
    cd_off = None
    for i in range(count):
        slot, so = struct.unpack_from(">II", d, dataoff + 12 + i * 8)
        bm, bl = struct.unpack_from(">II", d, dataoff + so)
        if bm != (CSMAGIC_CODEDIRECTORY if slot == 0 else CSMAGIC_REQUIREMENTS):
            errs.append(f"slot {slot}: unexpected magic 0x{bm:x}")
        if slot == 0:
            cd_off = dataoff + so
    if cd_off is None:
        errs.append("no CodeDirectory slot")
        return errs, None, (0, 0)

    (_cml, cdl, ver, flags, hash_offset, ident_offset,
     n_special, n_code, code_limit) = struct.unpack_from(">9I", d, cd_off)
    hash_size = d[cd_off + 36]
    page_shift = d[cd_off + 39]
    page = 1 << page_shift
    if code_limit != dataoff:
        errs.append(f"codeLimit 0x{code_limit:x} != dataoff 0x{dataoff:x}")
    if not flags & CS_ADHOC:
        errs.append("CodeDirectory is not ad-hoc")
    if n_code != (dataoff + page - 1) // page:
        errs.append("nCodeSlots does not match codeLimit")
    if hash_size != 32:
        errs.append(f"unexpected hashSize {hash_size}")
    if hash_offset < ident_offset + 1 + n_special * hash_size:
        errs.append(f"hashOffset {hash_offset} does not leave room for special slots")

    cname = d[cd_off + ident_offset:cd_off + cdl].split(b"\x00")[0].decode("utf-8", "replace")
    src = d[:code_limit]
    bad = 0
    for i in range(n_code):
        want = struct.unpack_from("32s", d, cd_off + hash_offset + i * 32)[0]
        chunk = src[i * page:(i + 1) * page]
        if len(chunk) < page:
            chunk += b"\x00" * (page - len(chunk))
        if hashlib.sha256(chunk).digest() != want:
            bad += 1
    if bad:
        errs.append(f"{bad}/{n_code} page hashes mismatch")
    return errs, cname, (n_code, page)


def main():
    path = sys.argv[1]
    with open(path, "rb") as f:
        m = MachO(f.read())
    m.repair_linkedit()
    m.repair_uuid()
    ident = sys.argv[2] if len(sys.argv) > 2 else (m.ident or "WechatDuo")
    if ident.startswith("/") or ident.startswith("@"):
        ident = os.path.splitext(os.path.basename(ident))[0] or "WechatDuo"
    tail = m.linkedit_tail()
    m.drop_orphan_blob(tail)
    dataoff, blob_len = m.sign(ident)
    with open(path, "wb") as f:
        f.write(bytes(m.d))
    print(f"signed {path}: ident={ident} dataoff=0x{dataoff:x} blob={blob_len} size={len(m.d)}")

    res = validate(path)
    if isinstance(res[0], list) and res[0]:
        print("VALIDATE FAILED:")
        for e in res[0]:
            print("  -", e)
        sys.exit(1)
    errs, cname, (n_code, page) = res
    print(f"validate OK: ident={cname} pages={n_code}@{page} "
          f"ad-hoc, LC=0x1D cmdsize=16, signature inside __LINKEDIT, ends at EOF")


if __name__ == "__main__":
    main()
