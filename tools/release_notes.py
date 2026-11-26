#!/usr/bin/env python3
"""Print the CHANGELOG.md section of a version:  python3 tools/release_notes.py 0.6.0  (exit 1 if it is missing)."""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ver = sys.argv[1].lstrip("v")
text = open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8").read()
m = re.search(rf"^## \[?{re.escape(ver)}\]?[^\n]*\n(.*?)(?=^## |\Z)", text, re.M | re.S)
if not m or not m.group(1).strip():
    sys.exit(f"CHANGELOG.md has no section for {ver}")
print(m.group(1).strip())
