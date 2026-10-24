#!/usr/bin/env python3
"""Conservative source-only release check. Never prints a detected secret's value."""
from pathlib import Path
import re
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
EXCLUDED = {'.git', 'build', 'dist', '__pycache__', '.venv-setup', '.venv', '__MACOSX'}
SUFFIXES = {'.swift', '.plist', '.entitlements', '.pbxproj', '.xcscheme',
            '.xcworkspacedata', '.png', '.md', '.txt', '.py', '.sh', '.command', '.json'}
ROOT_NAMES = {'.gitignore', '.gitattributes'}
PATTERNS = {
    'local account path': re.compile(rb'/(?:Users|home)/[A-Za-z0-9_.-]+/'),
    'private key': re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----[ \t\r\n]+[A-Za-z0-9+/]{32,}'),
    'GitHub token': re.compile(rb'\b(?:gh[pousr]_[A-Za-z0-9]{25,}|github_pat_[A-Za-z0-9_]{30,})'),
    'API key': re.compile(rb'\bsk-(?:proj-)?[A-Za-z0-9_-]{30,}'),
    'complete setup link': re.compile(rb'https://[^\s]+/identity#fp=[a-f0-9]{64}&token=[a-f0-9]{64}'),
}


def source_files(root=ROOT):
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root)
        if path.name == '.DS_Store' or any(part.startswith('._') for part in relative.parts):
            continue
        if any(part in EXCLUDED or part.startswith('.venv') for part in relative.parts):
            continue
        if path.is_symlink():
            yield path
        elif path.is_file():
            yield path


def issues(root=ROOT):
    found = []
    for path in source_files(root):
        relative = path.relative_to(root)
        label = relative.as_posix()
        if path.is_symlink():
            found.append((label, 'symlink not allowed in source release'))
            continue
        if 'xcuserdata' in relative.parts or path.name == '.DS_Store':
            found.append((label, 'private platform state'))
            continue
        if path.suffix not in SUFFIXES and label not in ROOT_NAMES:
            found.append((label, 'unexpected source file type'))
            continue
        data = path.read_bytes()
        if path.suffix == '.json' and not (path.name == 'Contents.json' and 'Assets.xcassets' in relative.parts):
            found.append((label, 'unexpected JSON outside asset catalog'))
        for description, pattern in PATTERNS.items():
            if pattern.search(data):
                found.append((label, description))
        if path.suffix == '.pbxproj':
            teams = re.findall(rb'DEVELOPMENT_TEAM\s*=\s*([^;]*);', data)
            if any(team.strip() not in (b'', b'""') for team in teams):
                found.append((label, 'selected signing team'))
        if path.suffix == '.png':
            if data[:8] != b'\x89PNG\r\n\x1a\n':
                found.append((label, 'invalid PNG header'))
                continue
            offset = 8
            while offset + 12 <= len(data):
                size = struct.unpack('>I', data[offset:offset + 4])[0]
                kind = data[offset + 4:offset + 8]
                if kind in {b'eXIf', b'tEXt', b'iTXt', b'zTXt', b'caBX'}:
                    found.append((label, 'unreviewed image metadata'))
                offset += size + 12
    return found


def main():
    failures = issues()
    for path, description in failures:
        print(f'FAIL {path}: {description}')
    if failures:
        print('Release check failed. No secret values were printed.')
        return 1
    print(f'PASS: {sum(1 for _ in source_files())} source files checked. No detected release blockers; this is not an exhaustive secret/anonymity audit.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
