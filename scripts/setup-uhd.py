#!/usr/bin/env python3
"""One-time pinned-HTTPS provisioning from the user's existing TwinVine install."""
import argparse
import base64
import datetime
import hashlib
import http.server
import ipaddress
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import ssl
import tempfile
import threading
import time


def find_config(twinvine, explicit=None):
    if explicit:
        path = explicit.expanduser()
        if not path.is_file():
            raise ValueError('The --config file does not exist.')
        return path
    services = twinvine.expanduser() / 'packages/envied/src/envied/services'
    candidates = sorted(set(services.glob('_repos/*/iP/config.yaml')) |
                        set(services.glob('iP/config.yaml')))
    if not candidates:
        raise ValueError('No TwinVine iP config.yaml found. Initialise its iP service, or pass --config /path/to/iP/config.yaml. See SETUP-UHD.md.')
    if len(candidates) > 1:
        raise ValueError('Multiple iP configurations found. Select the intended file with --config.')
    return candidates[0]


def load_config(path):
    import yaml
    try:
        config = yaml.safe_load(path.read_text())
    except yaml.YAMLError as error:
        raise ValueError('Invalid YAML in iP configuration. Details are suppressed to avoid printing credentials.') from error
    if not isinstance(config, dict):
        raise ValueError('The iP configuration must be a YAML mapping.')
    certificate = config.get('certificate')
    agent = config.get('user_agent')
    if not isinstance(certificate, str) or not certificate.strip():
        raise ValueError('The iP configuration needs a base64-encoded certificate field containing its PEM client certificate and private key.')
    if not isinstance(agent, str) or not agent.strip() or len(agent) >= 2048 or '\n' in agent or '\r' in agent:
        raise ValueError('The iP configuration needs a nonempty, single-line user_agent field shorter than 2048 characters.')
    try:
        pem = base64.b64decode(''.join(certificate.split()), validate=True)
    except ValueError as error:
        raise ValueError('The iP certificate field is not valid base64.') from error
    return pem, agent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--twinvine', type=Path, default=Path(os.environ.get('TWINVINE_DIR', str(Path.home() / 'TwinVine'))))
    parser.add_argument('--config', type=Path, help='Explicit iP config.yaml when automatic discovery does not match your installation')
    parser.add_argument('--check', action='store_true', help='Validate local setup without starting a server or printing credentials')
    parser.add_argument('--host', help='LAN IPv4 address of this Mac; use 127.0.0.1 only for local tests')
    parser.add_argument('--port', type=int, default=0)
    parser.add_argument('--output', type=Path, help='Optional private file for the setup URL; keep it out of Git')
    parser.add_argument('--timeout', type=int, default=900, help='Link lifetime in seconds, from 1 to 3600 (default: 900)')
    args = parser.parse_args()
    if not 1 <= args.timeout <= 3600 or not 0 <= args.port <= 65535:
        parser.error('Use --timeout 1..3600 and --port 0..65535.')
    try:
        pem, user_agent = load_config(find_config(args.twinvine, args.config))
    except ImportError:
        raise SystemExit('Missing setup dependencies. Follow SETUP-UHD.md to create .venv-setup and install scripts/requirements-setup.txt.')
    except (ValueError, OSError) as error:
        raise SystemExit(str(error))
    try:
        from cryptography import x509
    except ImportError:
        raise SystemExit('Missing cryptography. Install scripts/requirements-setup.txt in .venv-setup.')
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives.serialization import pkcs12
    from cryptography.x509.oid import NameOID

    try:
        certificate = x509.load_pem_x509_certificate(pem)
        key = serialization.load_pem_private_key(pem, password=None)
        if certificate.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo) != key.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo):
            raise ValueError('Certificate and private key do not match.')
        now = datetime.datetime.now(datetime.timezone.utc)
        if not certificate.not_valid_before_utc <= now < certificate.not_valid_after_utc:
            raise ValueError('The configured client certificate is expired or not valid yet.')
    except (ValueError, TypeError) as error:
        raise SystemExit('Invalid iP client identity: ' + str(error))
    if args.check:
        print('Local iP configuration is valid. No server started and no credentials displayed. BBC acceptance is checked only during playback.')
        return
    password = secrets.token_hex(24)
    p12 = pkcs12.serialize_key_and_certificates(b'BeebHD BBC UHD', key, certificate, None, serialization.BestAvailableEncryption(password.encode()))
    payload = json.dumps({'p12': base64.b64encode(p12).decode(), 'password': password, 'userAgent': user_agent}).encode()
    if args.host:
        host = args.host
    else:
        host = None
        if sys.platform == 'darwin':
            for interface in ['en0', 'en1', 'en2']:
                try:
                    value = subprocess.check_output(['/usr/sbin/ipconfig', 'getifaddr', interface], stderr=subprocess.DEVNULL, text=True).strip()
                    address = ipaddress.ip_address(value)
                    if address.version == 4 and address.is_private:
                        host = value
                        break
                except (subprocess.CalledProcessError, ValueError):
                    pass
        if not host:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
                probe.connect(('192.0.2.1', 9))
                host = probe.getsockname()[0]
    ip = ipaddress.ip_address(host)
    if ip.version != 4 or not any(ip in ipaddress.ip_network(block) for block in ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '127.0.0.0/8']):
        raise SystemExit('Bind to this Mac’s private LAN IPv4 address.')
    now = datetime.datetime.now(datetime.timezone.utc)
    server_key = ec.generate_private_key(ec.SECP256R1())
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'Beeb one-time setup')])
    server_cert = (x509.CertificateBuilder().subject_name(subject).issuer_name(subject)
        .public_key(server_key.public_key()).serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(minutes=1)).not_valid_after(now + datetime.timedelta(hours=1))
        .add_extension(x509.SubjectAlternativeName([x509.IPAddress(ip)]), critical=False)
        .sign(server_key, hashes.SHA256()))
    fingerprint = hashlib.sha256(server_cert.public_bytes(serialization.Encoding.DER)).hexdigest()
    token = secrets.token_hex(32)
    consumed = threading.Event()
    lock = threading.Lock()

    class Handler(http.server.BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(15)

        def do_GET(self):
            if self.path != '/identity' or not secrets.compare_digest(self.headers.get('Authorization', ''), 'Bearer ' + token):
                self.send_error(403)
                return
            with lock:
                if consumed.is_set():
                    self.send_error(410)
                    return
                consumed.set()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(payload)))
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(payload)
            self.wfile.flush()
            print('Transferred to the app. The helper will now stop.', flush=True)

        def log_message(self, *args):
            pass

    with tempfile.TemporaryDirectory(prefix='beebhd-setup-') as temporary:
        directory = Path(temporary)
        cert_path, key_path = directory / 'server.pem', directory / 'server-key.pem'
        cert_path.write_bytes(server_cert.public_bytes(serialization.Encoding.PEM))
        key_path.write_bytes(server_key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        os.chmod(key_path, 0o600)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(str(cert_path), str(key_path))
        http.server.ThreadingHTTPServer.daemon_threads = True
        server = http.server.ThreadingHTTPServer((host, args.port), Handler)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        server.timeout = 1
        url = f'https://{host}:{server.server_address[1]}/identity#fp={fingerprint}&token={token}'
        if args.output:
            fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, 'w') as output:
                output.write(url)
            os.chmod(args.output, 0o600)
            print('Setup URL saved to the requested private file.', flush=True)
        else:
            print('Paste this one-time setup URL in Beeb → Settings → Connect TwinVine:', flush=True)
            print(url, flush=True)
        print(f'Keep this window open until the Apple TV reports Connected. The link expires in {args.timeout} seconds.', flush=True)
        deadline = time.monotonic() + args.timeout
        try:
            while not consumed.is_set() and time.monotonic() < deadline:
                server.handle_request()
            if consumed.is_set():
                # Let the TLS response finish before closing the listener.
                time.sleep(2)
        finally:
            server.server_close()


if __name__ == '__main__':
    main()
