#!/usr/bin/env python3
"""Validate an ad-hoc signed dylib the way dyld / ChOma will read it.

The old version only checked "dataoff + datasize <= filesize", which is why
the broken v1.0.3 dylib sailed through CI. This one re-derives everything:
load-command structure, segment overlap, __LINKEDIT extents, SuperBlob and
CodeDirectory parsing, and every SHA-256 page hash. Exits non-zero on any
problem.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from adhoc_sign import validate  # noqa: E402

ok = True
for p in sys.argv[1:]:
    errs, ident, (pages, page) = validate(p)
    if errs:
        print(f"FAIL {p}:")
        for e in errs:
            print("  -", e)
        ok = False
    else:
        print(f"OK   {p}: ident={ident} pages={pages}@{page} "
              f"ad-hoc, signature inside __LINKEDIT, ends at EOF")
sys.exit(0 if ok else 1)
