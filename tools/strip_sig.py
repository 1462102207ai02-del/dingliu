#!/usr/bin/env python3
"""Remove a corrupt LC_CODE_SIGNATURE load command from a 64-bit Mach-O,
returning it to an unsigned state so ldid can sign from scratch.
The file length is preserved (zero padding) so symtab stroff+strsize
remains <= file size (ldid asserts on that otherwise).
Usage: strip_sig.py <path>"""
import struct
import sys

p = sys.argv[1]
with open(p, "rb") as f:
    d = bytearray(f.read())

orig_len = len(d)
if struct.unpack_from("<I", d, 0)[0] != 0xFEEDFACF:
    print(f"FAIL {p}: not a 64-bit Mach-O")
    sys.exit(1)

ncmds, = struct.unpack_from("<I", d, 16)
sizeofcmds, = struct.unpack_from("<I", d, 20)

off = 32
found = False
for _ in range(ncmds):
    cmd, size = struct.unpack_from("<II", d, off)
    if cmd == 0x1B:  # LC_CODE_SIGNATURE
        found = True
        break
    if size == 0:
        print(f"FAIL {p}: zero-size load command (desync)")
        sys.exit(1)
    off += size

if not found:
    print(f"OK   {p}: no LC_CODE_SIGNATURE (already unsigned)")
    sys.exit(0)

dataoff, datasize = struct.unpack_from("<II", d, off + 8)
# strip the 24-byte load command
del d[off:off + 24]
struct.pack_into("<I", d, 16, ncmds - 1)
struct.pack_into("<I", d, 20, sizeofcmds - 24)
# pad the freed space at the end of the load command region with zeros
end = 32 + (sizeofcmds - 24)
d[end:end + 24] = b"\x00" * 24
# keep the total file length unchanged (symtab may end at old EOF)
while len(d) < orig_len:
    d += b"\x00" * 16

with open(p, "wb") as f:
    f.write(d)
print(f"OK   {p}: stripped corrupt LC_CODE_SIGNATURE (off={dataoff} size={datasize}); unsigned now, len {orig_len} -> {len(d)}")
