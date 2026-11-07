"""Integration check requiring installed rclone; uses only a private local S3 server."""
import os
import pathlib
import secrets
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from upgrade import object_storage

with tempfile.TemporaryDirectory() as directory:
    root = pathlib.Path(directory)
    buckets = root / 'server'
    buckets.mkdir()
    checkpoint = root / 'checkpoint'
    checkpoint.mkdir()
    secret = secrets.token_hex(24)
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        port = probe.getsockname()[1]
    environment = {'AWS_ACCESS_KEY_ID': 'test', 'AWS_SECRET_ACCESS_KEY': secret,
                   'S3_ENDPOINT_URL': 'http://127.0.0.1:' + str(port)}
    for category in ['FILES', 'MODULES', 'SEARCH', 'EXPORTS', 'SNAPSHOT_IMPORTS']:
        name = category.lower().replace('_', '-')
        environment['S3_STORAGE_' + category + '_BUCKET'] = name
        (buckets / name).mkdir()
        (buckets / name / 'persisted').write_bytes(b'original contents')
    env = os.environ.copy()
    env['RCLONE_AUTH_KEY'] = '"test,' + secret + '"'
    with (root / 'server.log').open('w') as log:
        server = subprocess.Popen(['rclone', 'serve', 's3', str(buckets), '--addr', '127.0.0.1:' + str(port)],
                                  env=env, stdout=log, stderr=log)
        try:
            for _ in range(100):
                if server.poll() is not None:
                    raise RuntimeError('Private test S3 adapter exited')
                try:
                    urllib.request.urlopen(environment['S3_ENDPOINT_URL'], timeout=.2)
                    break
                except urllib.error.HTTPError:
                    break
                except OSError:
                    time.sleep(.05)
            else:
                raise RuntimeError('Private test S3 adapter did not start')
            object_storage(checkpoint, environment)
            (buckets / 'files' / 'persisted').unlink()
            (buckets / 'modules' / 'persisted').write_bytes(b'changed')
            (buckets / 'search' / 'unreferenced-new-object').write_bytes(b'keep this')
            object_storage(checkpoint, environment, restore=True)
            for bucket in buckets.iterdir():
                assert (bucket / 'persisted').read_bytes() == b'original contents'
            assert (buckets / 'search' / 'unreferenced-new-object').read_bytes() == b'keep this'
            print('Deleted and modified objects restored across five buckets; extra objects preserved')
        finally:
            server.terminate()
            server.wait(timeout=5)
