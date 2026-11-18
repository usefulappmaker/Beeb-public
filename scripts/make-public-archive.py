#!/usr/bin/env python3
"""Package checked source with neutral ZIP metadata; no signing or uploads."""
import importlib.util
from pathlib import Path
import sys
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('release_check', ROOT / 'scripts/check-public-release.py')
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


def main():
    if check.main():
        return 1
    project = (ROOT / 'BeebHD.xcodeproj/project.pbxproj').read_text()
    versions = set(re.findall(r'MARKETING_VERSION = ([0-9.]+);', project))
    if len(versions) != 1:
        raise SystemExit('App and extension must have one matching release version.')
    version = versions.pop()
    destination = ROOT / f'dist/Beeb-{version}-public-source.zip'
    destination.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in check.source_files():
            relative = path.relative_to(ROOT)
            info = zipfile.ZipInfo('Beeb-public/' + relative.as_posix(), (1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            mode = 0o755 if path.suffix in {'.sh', '.command', '.py'} else 0o644
            info.external_attr = (0o100000 | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, path.read_bytes())
    print('Created dist/' + destination.name + ' (source only; no Git history, local environments or builds).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
