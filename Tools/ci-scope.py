#!/usr/bin/env python3
"""Decides which CI jobs a change needs, from the files it touches.

    ci-scope.py <base> <head>      the files changed between two commits
    ci-scope.py --files <path>...  the given paths, to try the rules out

Prints GitHub step outputs: `check` (full, ios or none), `suites` (the
check suites an iOS-only change needs) and `ios` (true or false), then why.

- Documentation needs nothing.
- CI's own definition, the project, the packages, Config/, Shared/ and every
  Mac file the iOS targets also compile (Tools/iOS/shared-sources.txt) need
  everything.
- The iOS targets' own folders need the iOS jobs, and from `check` only the
  suites that compile iOS files; the iOS tests and their runner need only
  the iOS jobs.
- Anything else is the Mac's: `check` in full, no iOS jobs.

A full `check` runs only the suites whose scripts name a changed file (as a
path, a glob, a folder they search or one of their own helpers), unless a
changed file is one no suite names, or CI's own definition: then all of them.
"""
import fnmatch
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

DOCS = re.compile(r'(^|/)[^/]+\.md$|^docs/|^LICENSE$|^\.gitignore$')
# CI's own definition: every job, every suite.
CI = re.compile(r'^(\.github/workflows/ci\.yml|Tools/ci-scope\.py|Tools/check\.sh)$')
EVERYTHING = re.compile(r'^(\.github/workflows/ci\.yml|Tools/ci-scope\.py|Tools/check\.sh|openlist\.xcodeproj/'
                        r'|Package\.(swift|resolved)$|Config/|Shared/|Tools/iOS/|Tools/ios-sources\.py'
                        r'|Tools/add-ios-targets\.py)')
IOS_ONLY = re.compile(r'^(OpenlistiOS|OpenlistiOSWidget|OpenlistiOSShare|SharediOS)/')
# The iOS tests and their runner, which no check suite compiles.
IOS_TESTS = re.compile(r'^(OpenlistiOSTests|OpenlistiOSUITests)/|^Tools/run-ios-checks\.sh$')


def shared_with_ios():
    """The Mac files the iOS targets also compile, each a path or a folder."""
    paths = []
    for line in (ROOT / 'Tools/iOS/shared-sources.txt').read_text().splitlines():
        fields = line.split()
        if len(fields) == 3 and not line.startswith('#'):
            paths.append(f'{fields[1]}/{fields[2]}')
    return paths


ROOTS = r'(?:openlist|Shared|SharediOS|OpenlistiOS\w*|OpenlistWidget|OpenlistMCPHelper|MCPTransport|Tools|Config)'
PATH_TOKEN = re.compile(r'(?<![\w$/.-])(' + ROOTS + r'(?:/[\w+./*-]*)?)')
FIND_ROOTS = re.compile(r'\bfind\s+((?:[\w/.+-]+\s+)+)-')
NESTED = re.compile(r'\./Tools/run-([a-z-]+)-checks\.sh')
# Inputs that suites read without naming them in their scripts.
UNNAMED = {
    'mcp': ['MCPTransport/', 'Tools/MCPTransportTests/', 'Package.swift', 'Package.resolved'],
    'mcp-helper': ['Tools/verify-release.sh'],
    'signing': ['Tools/prepare-release-signing.py'],
    'ios-core': ['OpenlistiOS/', 'OpenlistiOSWidget/', 'OpenlistiOSShare/', 'SharediOS/', 'Shared/', 'openlist/Model/'],
}


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
        return refs + shared_with_ios() + ['Tools/ios-sources.py', 'Tools/add-ios-targets.py', 'Tools/iOS/']
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
    """The suites a change needs, in check.sh's order, or None for all."""
    suites = all_suites()
    refs = {suite: references(suite) for suite in suites}
    needed = set()
    for path in files:
        if CI.search(path):
            return None
        naming = {suite for suite in suites if any(names(ref, path) for ref in refs[suite])}
        if not naming:
            return None
        needed |= naming
    return [suite for suite in suites if suite in needed]


def suites_reading_ios():
    """The check suites whose scripts compile files from the iOS targets."""
    names = []
    for script in sorted((ROOT / 'Tools').glob('run-*-checks.sh')):
        name = script.name[len('run-'):-len('-checks.sh')]
        if name != 'ios' and re.search(r'\b(OpenlistiOS\w*|SharediOS)/|ios-sources\.py', script.read_text()):
            names.append(name)
    return names


def scope(files):
    shared = shared_with_ios()
    needs_mac = needs_ios = needs_ios_suites = False
    reasons = []
    for path in files:
        if DOCS.search(path):
            continue
        if EVERYTHING.search(path) or any(path == s or path.startswith(s + '/') for s in shared):
            needs_mac = needs_ios = True
            reasons.append(f'{path}: shared or CI')
        elif IOS_ONLY.search(path):
            needs_ios = needs_ios_suites = True
            reasons.append(f'{path}: iOS')
        elif IOS_TESTS.search(path):
            needs_ios = True
            reasons.append(f'{path}: iOS tests')
        else:
            needs_mac = True
            reasons.append(f'{path}: Mac')
    check = 'full' if needs_mac else 'ios' if needs_ios_suites else 'none'
    if check == 'ios':
        suites = suites_reading_ios()
    elif check == 'full':
        checked = [path for path in files if not DOCS.search(path) and not IOS_TESTS.search(path)]
        suites = suites_naming(checked) or []
    else:
        suites = []
    return check, suites, needs_ios, reasons


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
    check, suites, ios, reasons = scope(files)
    print(f'check={check}')
    print(f'suites={" ".join(suites)}')
    print(f'ios={"true" if ios else "false"}')
    for reason in reasons[:40]:
        print(reason, file=sys.stderr)
    print(f'{len(files)} files changed: check {check}{" (" + " ".join(suites) + ")" if suites else ""}, '
          f'iOS jobs {"yes" if ios else "no"}', file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
