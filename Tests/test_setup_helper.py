"""Offline provisioning checks using synthetic short-lived identities only."""
import base64
import datetime
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('setup_helper', ROOT / 'scripts/setup-uhd.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class SetupTests(unittest.TestCase):
    def test_discovery_handles_direct_remote_and_ambiguity(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with self.assertRaises(ValueError):
                helper.find_config(root)
            direct = root / 'packages/envied/src/envied/services/iP/config.yaml'
            direct.parent.mkdir(parents=True)
            direct.write_text('test')
            self.assertEqual(helper.find_config(root), direct)
            remote = root / 'packages/envied/src/envied/services/_repos/service/iP/config.yaml'
            remote.parent.mkdir(parents=True)
            remote.write_text('test')
            with self.assertRaises(ValueError):
                helper.find_config(root)
            self.assertEqual(helper.find_config(root, remote), remote)

    def test_bad_yaml_shape_base64_and_header_injection(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'config.yaml'
            for text in ['[]', 'certificate: invalid!\nuser_agent: test',
                         'certificate: dGVzdA==\nuser_agent: "bad\\r\\nheader"']:
                path.write_text(text)
                with self.assertRaises(ValueError):
                    helper.load_config(path)

    def test_check_valid_expired_and_mismatched_identities_without_server(self):
        from cryptography import x509
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import ec
        from cryptography.x509.oid import NameOID
        import yaml
        now = datetime.datetime.now(datetime.timezone.utc)
        key = ec.generate_private_key(ec.SECP256R1())
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'Synthetic setup test')])
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'config.yaml'
            for mode in ['valid', 'expired', 'mismatch']:
                cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
                        .public_key(key.public_key()).serial_number(x509.random_serial_number())
                        .not_valid_before(now - datetime.timedelta(days=2))
                        .not_valid_after(now + datetime.timedelta(days=1) if mode != 'expired' else now - datetime.timedelta(days=1))
                        .sign(key, hashes.SHA256()))
                selected = ec.generate_private_key(ec.SECP256R1()) if mode == 'mismatch' else key
                pem = cert.public_bytes(serialization.Encoding.PEM) + selected.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
                path.write_text(yaml.safe_dump({'certificate': base64.b64encode(pem).decode(), 'user_agent': 'Synthetic test agent'}))
                result = subprocess.run([sys.executable, str(ROOT / 'scripts/setup-uhd.py'), '--config', str(path), '--check'], capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0 if mode == 'valid' else 1)
                self.assertNotIn(base64.b64encode(pem).decode(), result.stdout + result.stderr)
                self.assertNotIn('https://', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
