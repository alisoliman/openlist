#!/usr/bin/env python3
"""Prints the Swift files an Xcode target compiles, one path per line, as
openlist.xcodeproj/project.pbxproj assigns them.

Emulates objectVersion 77 synchronized folders: a target compiles every file
in the folders listed in its fileSystemSynchronizedGroups, minus the exact
paths in exception sets for that target on those folders, plus the exact
paths in exception sets for that target on folders it does not list. For
OpenlistiOS and OpenlistiOSWidget this matches the SwiftCompile lines of an
xcodebuild log; for the Mac app it is `find openlist Shared -name '*.swift'`.

    Tools/ios-sources.py OpenlistiOS            # everything the target compiles
    Tools/ios-sources.py OpenlistiOS --shared   # only files lent by other targets' folders
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
text = (ROOT / "openlist.xcodeproj/project.pbxproj").read_text()


def block(ident):
    match = re.search(rf"\n\t\t{ident} /\*[^\n]*?\*/ = \{{\n(.*?)\n\t\t\}};", text, re.S)
    if not match:
        raise SystemExit(f"object {ident} not found")
    return match.group(1)


def ids(body, key):
    match = re.search(rf"\t{key} = \(\n(.*?)\t*\);", body, re.S)
    return re.findall(r"([0-9A-F]{24})", match.group(1)) if match else []


def value(body, key):
    match = re.search(rf"\t{key} = (\"[^\"]*\"|[^;]+);", body)
    return match.group(1).strip('"') if match else None


def strings(body, key):
    match = re.search(rf"\t{key} = \(\n(.*?)\t*\);", body, re.S)
    return [s.strip().rstrip(",").strip('"') for s in match.group(1).splitlines() if s.strip()] if match else []


def swift_files(root):
    folder = ROOT / root
    return {p.relative_to(ROOT) for p in folder.rglob("*.swift") if p.is_file()} if folder.is_dir() else set()


name = sys.argv[1] if len(sys.argv) > 1 else ""
shared_only = "--shared" in sys.argv[2:]
target = re.search(rf"\n\t\t([0-9A-F]{{24}}) /\* {re.escape(name)} \*/ = \{{\n\t\t\tisa = PBXNativeTarget;", text)
if not target:
    raise SystemExit(f"no target named {name!r} in openlist.xcodeproj")
target_id = target.group(1)
owned = set(ids(block(target_id), "fileSystemSynchronizedGroups"))
files = set()
pattern = r"\n\t\t([0-9A-F]{24}) /\*[^\n]*?\*/ = \{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;"
for group_id in re.findall(pattern, text):
    group = block(group_id)
    root = Path(value(group, "path"))
    listed = set()
    for exception_id in ids(group, "exceptions"):
        exception = block(exception_id)
        if value(exception, "isa") == "PBXFileSystemSynchronizedBuildFileExceptionSet" and \
                value(exception, "target").split()[0] == target_id:
            listed |= set(strings(exception, "membershipExceptions"))
    if group_id in owned:
        if not shared_only:
            files |= {p for p in swift_files(root) if str(p.relative_to(root)) not in listed}
    else:
        files |= {root / p for p in listed if p.endswith(".swift")}
for path in sorted(files):
    print(path)
