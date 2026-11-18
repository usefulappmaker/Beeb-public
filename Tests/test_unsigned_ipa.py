"""Unsigned release invariants for both the app and its nested Top Shelf extension."""
import importlib.util
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('unsigned_check', ROOT / 'scripts/check-unsigned-ipa.py')
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


class UnsignedReleaseTests(unittest.TestCase):
    def inspect_fixture(self, signed_extension=False, extension_build='35'):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'fixture.ipa'
            with zipfile.ZipFile(path, 'w') as archive:
                for prefix, identifier, executable, build in [
                    ('Payload/BeebHD.app/', 'org.beebplayer.Beeb', 'BeebHD', '35'),
                    ('Payload/BeebHD.app/PlugIns/BeebTopShelf.appex/', 'org.beebplayer.Beeb.TopShelf', 'BeebTopShelf', extension_build),
                ]:
                    info = dict(CFBundleIdentifier=identifier, CFBundleExecutable=executable,
                                CFBundleDisplayName='Beeb', CFBundleSupportedPlatforms=['AppleTVOS'],
                                CFBundleShortVersionString='0.10.8', CFBundleVersion=build)
                    info['CFBundleURLTypes'] = [dict(CFBundleURLSchemes=['beeb'])]
                    if executable == 'BeebTopShelf':
                        info['NSExtension'] = dict(NSExtensionPointIdentifier='com.apple.tv-top-shelf')
                    signature = executable == 'BeebTopShelf' and signed_extension
                    data = struct.pack('<8I', 0xfeedfacf, 0x0100000c, 0, 2, int(signature), 16 if signature else 0, 0, 0)
                    if signature:
                        data += struct.pack('<4I', 0x1d, 16, 0, 0)
                    archive.writestr(prefix+'Info.plist', plistlib.dumps(info))
                    archive.writestr(prefix+executable, data)
            return check.inspect(path)

    def test_accepts_matching_unsigned_app_and_extension(self):
        self.assertEqual(self.inspect_fixture(), [])

    def test_rejects_signature_in_nested_extension(self):
        self.assertTrue(any('code signature' in error for error in self.inspect_fixture(signed_extension=True)))

    def test_rejects_mismatched_extension_build(self):
        self.assertTrue(any('version/build' in error for error in self.inspect_fixture(extension_build='34')))


if __name__ == '__main__':
    unittest.main()
