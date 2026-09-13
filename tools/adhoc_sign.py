#!/usr/bin/env python3
"""Ad-hoc code signer for 64-bit Mach-O dylibs (v2).

Why this exists
---------------
Theos built on Linux emits a dylib whose LC_CODE_SIGNATURE carries garbage
offsets, and `ldid` (procursus builds) only appends a blob without writing the
load command back. TrollFools' `ct_bypass` (ChOma) then rejects the file with
"no code signature found" and the injection never happens.

v1 of this script had a fatal bug: it patched __LINKEDIT at lc+40, which is the
*fileoff* field, not filesize. That collapsed __LINKEDIT onto __TEXT, the
segments overlapped, and every strict Mach-O parser (ChOma / dyld) treated the
file as structurally broken -- exactly the "no code signature found" above.

Layout of LC_SEGMENT_64 (must not be re-derived from memory again):
    +0  cmd       +4  cmdsize    +8  segname[16]
    +24 vmaddr    +32 vmsize     +40 fileoff    +48 filesize

What v2 does
------------
  1. repairs a corrupted __LINKEDIT fileoff (never writes to it otherwise)
  2. strips the corrupt LC_CODE_SIGNATURE and any orphan trailing blob
  3. inserts a fresh LC_CODE_SIGNATURE
  4. writes a real ad-hoc SuperBlob (CodeDirectory v0x20400, SHA-256,
     empty Requirements set), zero-padded page hashing, null Info slot
  5. grows only __LINKEDIT filesize/vmsize
  6. self-validates and exits non-zero if anything is off

Usage: adhoc_sign.py <path> [identifier]
"""
import hashlib
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
LC_CODE_SIGNATURE = 0x1B
LC_SYMTAB = 0x02
LC_DYLD_INFO = 0x22
LC_DYLD_INFO_ONLY = 0x80000022
LINKEDIT_DATA_CMDS = (0x1B, 0x1C, 0x25, 0x26, 0x29, 0x2B, 0x2E, 0x33, 0x80000033)


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

    # ------------------------------------------------------------------ scan
    def scan(self):
        d = self.d
        self.segs = {}          # name -> [lc_off, vmaddr, vmsize, fileoff, filesize]
        self.sig_lc = None      # lc_off or None
        self.sig = None         # (dataoff, datasize)
        self.symtab = None
        self.ident = None
        off = 32
        for _ in range(self.ncmds):
            cmd, size = struct.unpack_from("<II", d, off)
            if cmd == LC_SEGMENT_64:
                name = d[off + 8:off + 24].split(b"\x00")[0].decode()
                vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", d, off + 24)
                self.segs[name] = [off, vmaddr, vmsize, fileoff, filesize]
            elif cmd == LC_CODE_SIGNATURE:
                self.sig_lc = off
                self.sig = struct.unpack_from("<II", d, off + 8)
            elif cmd == LC_SYMTAB:
                self.symtab = struct.unpack_from("<IIII", d, off + 8)
            elif cmd == LC_ID_DYLIB:
                name_off, = struct.unpack_from("<I", d, off + 8)
                self.ident = d[off + name_off:off + size].split(b"\x00")[0].decode()
            off += size

    # --------------------------------------------------------- linkedit tail
    def linkedit_tail(self):
        """Last byte of real __LINKEDIT content (where a signature may start)."""
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
            end = max(end, self.segs["__LINKEDIT"][3])  # fileoff
        return end

    # ------------------------------------------------------------- repair LE
    def repair_linkedit(self):
        """Fix a __LINKEDIT fileoff that a broken signer has clobbered."""
        if "__LINKEDIT" not in self.segs:
            return
        lc, vmaddr, _vmsize, fileoff, _filesize = self.segs["__LINKEDIT"]
        slides = [s[1] - s[3] for n, s in self.segs.items() if n != "__LINKEDIT"]
        slide = min(slides) if slides else 0
        want = vmaddr - slide
        if fileoff != want:
            print(f"repair __LINKEDIT fileoff 0x{fileoff:x} -> 0x{want:x} "
                  f"(vmaddr=0x{vmaddr:x}, slide=0x{slide:x})")
            struct.pack_into("<Q", self.d, lc + 40, want)
            self.segs["__LINKEDIT"][3] = want
            self.scan()

    # ------------------------------------------------------------ strip sig
    def drop_orphan_blob(self, tail):
        """Drop the orphan blob the corrupt LC points at.

        NOTE: we never delete bytes out of the load-command area. __TEXT starts
        at fileoff 0 and contains the header + all load commands, so removing
        bytes there shifts every section's contents by that amount while the
        recorded offsets stay put -- silently corrupting the whole image.
        LC_CODE_SIGNATURE is a 16-byte linkedit_data_command; v1 assumed 24 and
        truncated 8 bytes of live data because of it.
        """
        if len(self.d) > tail:
            print(f"truncated orphan trailing data: {len(self.d)} -> {tail}")
            del self.d[tail:]

    def lc_slot(self):
        """Reuse the existing LC_CODE_SIGNATURE, else claim 16 bytes of padding."""
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

    # -------------------------------------------------------------- sign it
    def sign(self, ident):
        d = self.d
        # pad the file out to the 16-byte aligned signature start
        dataoff = align(len(d), 16)
        if dataoff > len(d):
            d += b"\x00" * (dataoff - len(d))

        # --- locate / insert LC_CODE_SIGNATURE -----------------------------
        lc_pos = self.lc_slot()

        # --- sizes first: everything that changes bytes inside [0, dataoff)
        #     must be written BEFORE the page hashes are taken --------------
        ident_b = ident.encode() + b"\x00"
        cd_hdr_len = 88
        n_special = 2                       # -1 Info (null), -2 Requirements
        n_code = (dataoff + PAGE_SIZE - 1) // PAGE_SIZE
        # hashOffset points at the START of the hash array, and the special
        # slots are the first entries of that array -- do not add them here.
        ident_off = cd_hdr_len
        hash_off = ident_off + len(ident_b)
        cd_len = hash_off + (n_special + n_code) * 32
        req = blob(CSMAGIC_REQUIREMENTS, struct.pack(">I", 0))
        sb_len = 12 + 16 + cd_len + len(req)

        struct.pack_into("<II", d, lc_pos + 8, dataoff, sb_len)
        if "__LINKEDIT" in self.segs:
            lc, _vmaddr, _vmsize, fileoff, _filesize = self.segs["__LINKEDIT"]
            new_filesize = dataoff + sb_len - fileoff
            new_vmsize = align(new_filesize, PAGE_SIZE)
            struct.pack_into("<Q", d, lc + 48, new_filesize)
            struct.pack_into("<Q", d, lc + 32, new_vmsize)
            self.segs["__LINKEDIT"][4] = new_filesize
            self.segs["__LINKEDIT"][2] = new_vmsize

        # --- CodeDirectory v0x20400 ---------------------------------------
        cd = bytearray(cd_len)
        struct.pack_into(">IIII", cd, 0, CSMAGIC_CODEDIRECTORY, cd_len, 0x20400, CS_ADHOC)
        struct.pack_into(">I", cd, 16, hash_off)
        struct.pack_into(">I", cd, 20, ident_off)
        struct.pack_into(">I", cd, 24, n_special)
        struct.pack_into(">I", cd, 28, n_code)
        struct.pack_into(">I", cd, 32, dataoff)     # codeLimit
        cd[36] = 32                                  # hashSize SHA-256
        cd[37] = 2                                   # hashType SHA-256
        cd[38] = 0                                   # platform
        cd[39] = PAGE_SHIFT
        # v0x20300: spare3(52)=0, codeLimit64(56)=dataoff
        struct.pack_into(">Q", cd, 56, dataoff)
        # v0x20400: execSegBase / execSegLimit / execSegFlags
        text = self.segs.get("__TEXT")
        if text:
            struct.pack_into(">QQQ", cd, 64, text[1], text[2], 0)
        cd[ident_off:ident_off + len(ident_b)] = ident_b

        # special slots: -1 Info (null hash, no Info.plist), -2 Requirements
        hashes = bytearray(32) + hashlib.sha256(req).digest()
        # code slots: every page, last one zero-padded like codesign does
        for i in range(n_code):
            chunk = bytes(d[i * PAGE_SIZE:(i + 1) * PAGE_SIZE])
            if len(chunk) < PAGE_SIZE:
                chunk += b"\x00" * (PAGE_SIZE - len(chunk))
            hashes += hashlib.sha256(chunk).digest()
        cd[hash_off:hash_off + len(hashes)] = hashes
        cd = bytes(cd)

        # --- SuperBlob -----------------------------------------------------
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
    """Second pass, independent of the writer: re-derive everything."""
    with open(path, "rb") as f:
        d = f.read()
    m = MachO(d)
    m.scan()
    errs = []

    size = len(d)
    if m.sig is None:
        return ["LC_CODE_SIGNATURE missing"], None, (0, 0)
    dataoff, datasize = m.sig

    if dataoff + datasize != size:
        errs.append(f"signature does not end at EOF: {dataoff + datasize} != {size}")
    if dataoff % 16:
        errs.append(f"dataoff not 16-aligned: 0x{dataoff:x}")

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

    # segments must not overlap in the file
    order = sorted(m.segs.values(), key=lambda s: s[3])
    for a, b in zip(order, order[1:]):
        if a[3] + a[4] > b[3]:
            errs.append(f"segments overlap: end 0x{a[3]+a[4]:x} > next start 0x{b[3]:x}")

    # superblob / code directory
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

    cname = d[cd_off + ident_offset:cd_off + cdl].split(b"\x00")[0].decode("utf-8", "replace")
    # recompute page hashes over [0, codeLimit) only, zero-padded to a page
    src = d[:code_limit]
    bad = 0
    for i in range(n_code):
        want = struct.unpack_from("32s", d, cd_off + hash_offset + (n_special + i) * 32)[0]
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
    ident = sys.argv[2] if len(sys.argv) > 2 else (m.ident or "dingliu")
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
          f"ad-hoc, signature inside __LINKEDIT, ends at EOF")


if __name__ == "__main__":
    main()
