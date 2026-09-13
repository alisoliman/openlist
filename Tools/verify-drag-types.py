#!/usr/bin/env python3
"""Verify registered private transport types in source or built app metadata."""
import plistlib
import sys
from pathlib import Path

path = Path(sys.argv[1])
kind = sys.argv[2] if len(sys.argv) > 2 else "app"

def fail(reason):
    raise SystemExit(f"Invalid {kind} bundle: {path}: UTExportedTypeDeclarations {reason}")

try:
    info = plistlib.loads(path.read_bytes())
except (OSError, plistlib.InvalidFileException) as error:
    fail(f"cannot read Info.plist ({error})")
exports = info.get("UTExportedTypeDeclarations")
if not isinstance(exports, list):
    fail("must declare private drag types and the library backup type")
for identifier, conformance in [
    ("app.openlist.block-drag", "public.data"),
    ("app.openlist.inbox-order", "public.data"),
    ("solimanali.openlist.library-backup", "com.apple.package"),
]:
    matches = [item for item in exports if isinstance(item, dict) and item.get("UTTypeIdentifier") == identifier]
    if len(matches) != 1:
        fail(f"must export {identifier} exactly once")
    parents = matches[0].get("UTTypeConformsTo")
    if not isinstance(parents, list) or conformance not in parents:
        fail(f"{identifier} must conform to {conformance}")
print(f"Verified private drag types and library backup export: {path}")
