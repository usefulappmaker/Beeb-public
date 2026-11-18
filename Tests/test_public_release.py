"""Release boundary tests with deliberately synthetic disposable data."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('release_check', ROOT / 'scripts/check-public-release.py')
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


class ReleaseTests(unittest.TestCase):
    def test_rejects_signing_profiles_teams_and_local_paths(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'private.mobileprovision').write_bytes(b'synthetic')
            (root / 'project.pbxproj').write_text('DEVELOPMENT_TEAM = EXAMPLE123;')
            (root / 'README.md').write_text('/' + 'Users' + '/example/account/file')
            descriptions = [message for _, message in check.issues(root)]
            self.assertIn('unexpected source file type', descriptions)
            self.assertIn('selected signing team', descriptions)
            self.assertIn('local account path', descriptions)

    def test_private_key_parser_marker_is_not_key_material(self):
        marker = b'-----BEGIN ' + b'PRIVATE KEY-----'
        self.assertIsNone(check.PATTERNS['private key'].search(marker))
        self.assertIsNotNone(check.PATTERNS['private key'].search(marker + b'\n' + b'A' * 64 + b'\n'))

    def test_build_and_git_history_never_enter_source_archive(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for directory in ['build', 'dist', '.git', '.venv-setup']:
                path = root / directory / 'private.txt'
                path.parent.mkdir()
                path.write_text('excluded synthetic data')
            (root / 'README.md').write_text('public documentation')
            (root / '.DS_Store').write_bytes(b'synthetic Finder metadata')
            (root / '._README.md').write_bytes(b'synthetic AppleDouble metadata')
            (root / '__MACOSX').mkdir()
            (root / '__MACOSX/._README.md').write_bytes(b'synthetic archive metadata')
            self.assertEqual([p.name for p in check.source_files(root)], ['README.md'])

    def test_symlinks_cannot_import_external_files(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'README.md').symlink_to('/nonexistent-synthetic-target')
            self.assertTrue(any('symlink' in message for _, message in check.issues(root)))


if __name__ == '__main__':
    unittest.main()
