#!/usr/bin/env python3
"""Decides what CI runs for a change, from the files it touches.

    ci-scope.py <base> <head>      the files changed between two commits
    ci-scope.py --files <path>...  the given paths, to try the rules out

Prints GitHub step outputs, then why:
  check     full, ios or none: the check job, all it can do or only suites
  suites    the check suites to run; none listed means all of them
  release   true when the Mac app's release build is worth checking
  ios       true when the iOS jobs run
  parts     which of the three iOS parts run, as JSON

- Documentation needs nothing.
- CI's own definition, the project, the packages, Config/, Shared/ and every
  Mac file the iOS targets also compile (Tools/iOS/shared-sources.txt) need
  everything.
- The iOS targets' own folders need the iOS jobs, and from `check` only the
  suites that compile iOS files. The iOS tests need only their own part:
  unit tests run in the first; a UI test class in the part that names it,
  unless its file also declares helpers other classes use.
- Anything else is the Mac's: `check` without the iOS jobs, and the release
  build unless only check suites and their scripts changed.

A full `check` runs only the suites whose scripts name a changed file (as a
path, a glob, a folder they search or one of their own helpers), unless a
changed file is one no suite names, or CI's own definition: then all of them.
"""
import fnmatch
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

DOCS = re.compile(r'(^|/)[^/]+\.md$|^docs/|^LICENSE$|^\.gitignore$')
# CI's own definition: every job, every suite.
CI = re.compile(r'^(\.github/workflows/ci\.yml|Tools/ci-scope\.py|Tools/check\.sh)$')
SHARED = re.compile(r'^(openlist\.xcodeproj/|Package\.(swift|resolved)$|Config/|Shared/|Tools/iOS/'
                    r'|Tools/ios-sources\.py$|Tools/add-ios-targets\.py$)')
IOS_APP = re.compile(r'^(OpenlistiOS|OpenlistiOSWidget|OpenlistiOSShare|SharediOS)/')
UNIT_TESTS = re.compile(r'^OpenlistiOSTests/')
UI_TESTS = re.compile(r'^OpenlistiOSUITests/(\w+)\.swift$')
# Check suites and what only they read: no release build for these.
CHECKS_ONLY = re.compile(r'^Tools/(run-[a-z-]+-checks\.sh$|\w+Checks/)')

ROOTS = r'(?:openlist|Shared|SharediOS|OpenlistiOS\w*|OpenlistWidget|OpenlistMCPHelper|MCPTransport|Tools|Config)'
PATH_TOKEN = re.compile(r'(?<![\w$/.-])(' + ROOTS + r'(?:/[\w+./*-]*)?)')
FIND_ROOTS = re.compile(r'\bfind\s+((?:[\w/.+-]+\s+)+)-')
NESTED = re.compile(r'\./Tools/run-([a-z-]+)-checks\.sh')
# Inputs that suites read without naming them in their scripts.
UNNAMED = {
    'mcp': ['MCPTransport/', 'Tools/MCPTransportTests/', 'Package.swift', 'Package.resolved'],
    'mcp-helper': ['Tools/verify-release.sh'],
    'signing': ['Tools/prepare-release-signing.py'],
}


def shared_with_ios():
    """The Mac files the iOS targets also compile, each a path or a folder."""
    paths = []
    for line in (ROOT / 'Tools/iOS/shared-sources.txt').read_text().splitlines():
        fields = line.split()
        if len(fields) == 3 and not line.startswith('#'):
            paths.append(f'{fields[1]}/{fields[2]}')
    return paths


def all_suites():
    """check.sh's suites, in its order."""
    text = (ROOT / 'Tools/check.sh').read_text()
    return re.search(r'SUITES=\(([^)]*)\)', text).group(1).split()


def references(suite, seen=None):
    """What a suite's script names: paths, globs and folders, its nested
    suites' too."""
    seen = seen if seen is not None else set()
    if suite in seen:
        return []
    seen.add(suite)
    script = f'Tools/run-{suite}-checks.sh'
    text = (ROOT / script).read_text()
    refs = [script] + UNNAMED.get(suite, [])
    if suite == 'ios-core':
        # Its paths are patterns over what Tools/ios-sources.py lists.
        return refs + shared_with_ios() + ['OpenlistiOS/', 'OpenlistiOSWidget/', 'OpenlistiOSShare/', 'SharediOS/',
                                           'Shared/', 'openlist/Model/', 'Tools/ios-sources.py',
                                           'Tools/add-ios-targets.py', 'Tools/iOS/']
    for token in PATH_TOKEN.findall(text) + [d for m in FIND_ROOTS.findall(text) for d in m.split()]:
        token = token.rstrip('/.')
        if not token or '$' in token:
            continue
        if (ROOT / token).is_dir():
            refs.append(token + '/')
        else:
            refs.append(token)
            # A suite's own helpers and fixtures live beside what it names.
            folder = re.match(r'Tools/\w+Checks/', token)
            if folder:
                refs.append(folder.group(0))
    for nested in NESTED.findall(text):
        refs += references(nested, seen)
    return refs


def names(ref, path):
    if ref.endswith('/'):
        return path.startswith(ref)
    if any(c in ref for c in '*?['):
        return fnmatch.fnmatchcase(path, ref)
    return path == ref or path.startswith(ref + '/')


def suites_naming(files):
    """The suites these files need, in check.sh's order, or [] for all."""
    suites = all_suites()
    refs = {suite: references(suite) for suite in suites}
    needed = set()
    for path in files:
        if CI.search(path):
            return []
        naming = {suite for suite in suites if any(names(ref, path) for ref in refs[suite])}
        if not naming:
            return []
        needed |= naming
    return [suite for suite in suites if suite in needed]


def suites_reading_ios():
    """The check suites whose scripts compile files from the iOS targets."""
    found = []
    for suite in all_suites():
        text = (ROOT / f'Tools/run-{suite}-checks.sh').read_text()
        if suite == 'ios-core' or re.search(r'\b(OpenlistiOS\w*|SharediOS)/', text):
            found.append(suite)
    return found


def ui_test_part(path):
    """The iOS part that runs a UI test class's file, or None when the file
    may hold what other classes use."""
    match = UI_TESTS.match(path)
    if not match or not (ROOT / path).exists():
        return None
    # Anything declared outside the class, such as an extension, is shared.
    if re.search(r'^(extension|func|struct|enum|let|var)\b', (ROOT / path).read_text(), re.M):
        return None
    runner = (ROOT / 'Tools/run-ios-checks.sh').read_text()
    for part in (1, 2):
        listed = re.search(rf'^PART{part}=\(([^)]*)\)', runner, re.M).group(1).split()
        if match.group(1) in listed:
            return part
    return 3


def scope(files):
    shared = shared_with_ios()
    mac, release, ios_suites = [], False, False
    parts = set()
    reasons = []
    for path in files:
        if DOCS.search(path):
            continue
        if CI.search(path) or SHARED.search(path) or any(names(s, path) for s in shared):
            mac.append(path)
            release = True
            parts |= {1, 2, 3}
            reasons.append(f'{path}: shared or CI')
        elif IOS_APP.search(path):
            ios_suites = True
            parts |= {1, 2, 3}
            reasons.append(f'{path}: iOS')
        elif UNIT_TESTS.search(path):
            parts.add(1)
            reasons.append(f'{path}: iOS unit tests')
        elif path.startswith('OpenlistiOSUITests/') or path == 'Tools/run-ios-checks.sh':
            part = ui_test_part(path)
            parts |= {part} if part else {1, 2, 3}
            reasons.append(f'{path}: iOS UI tests, part {part or "all"}')
        else:
            mac.append(path)
            release = release or not CHECKS_ONLY.search(path)
            reasons.append(f'{path}: Mac')
    if mac:
        check, suites = 'full', suites_naming(mac)
    elif ios_suites:
        check, suites = 'ios', suites_reading_ios()
    else:
        check, suites = 'none', []
    return {'check': check, 'suites': ' '.join(suites), 'release': str(release).lower(),
            'ios': str(bool(parts)).lower(), 'parts': json.dumps(sorted(parts))}, reasons


def main(argv):
    if argv[:1] == ['--files']:
        files = argv[1:]
    elif len(argv) == 2 and not set(argv[0]) <= {'0'}:
        out = subprocess.run(['git', 'diff', '--name-only', f'{argv[0]}...{argv[1]}'], cwd=ROOT,
                             capture_output=True, text=True)
        # Commits it can't compare (history rewritten): everything.
        files = out.stdout.split() if out.returncode == 0 else ['.github/workflows/ci.yml']
    else:
        # No base to compare with (a manual run, a new branch): everything.
        files = ['.github/workflows/ci.yml']
    outputs, reasons = scope(files)
    for key, value in outputs.items():
        print(f'{key}={value}')
    for reason in reasons[:40]:
        print(reason, file=sys.stderr)
    print(f'{len(files)} files changed: ' + ', '.join(f'{k} {v}' for k, v in outputs.items()), file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
