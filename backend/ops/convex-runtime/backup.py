#!/usr/bin/env python3
"""Save a full logical export, private recovery configuration and verified offsite copies."""
import argparse
import base64
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import tarfile
import zipfile
from rehearse import PROJECTS
from verify import PORTS

SOURCE = pathlib.Path(__file__).resolve().parent


def verify_export(archive):
    count = 0
    with zipfile.ZipFile(archive) as zipped:
        if zipped.testzip() is not None:
            raise RuntimeError('Backup export CRC failed')
        names = zipped.namelist()
        if 'README.md' not in names or not any(n.endswith('/documents.jsonl') for n in names):
            raise RuntimeError('Backup does not contain application documents')
        for metadata in (n for n in names if n.endswith('_storage/documents.jsonl')):
            prefix = metadata.removesuffix('documents.jsonl')
            files = {n.removeprefix(prefix).split('.')[0]: n for n in names if n.startswith(prefix)}
            for line in zipped.read(metadata).splitlines():
                row = json.loads(line)
                member = files[row['_id']]
                if zipped.getinfo(member).file_size != row['size']:
                    raise RuntimeError('Exported storage file size differs from its metadata')
                with zipped.open(member) as stream:
                    digest = hashlib.file_digest(stream, 'sha256').digest()
                if row['sha256'] not in [digest.hex(), base64.b64encode(digest).decode()]:
                    raise RuntimeError('Exported storage file contents differ from their metadata')
                count += 1
    return count


def backup(project, destination, manifest):
    destination.mkdir(parents=True, exist_ok=False, mode=0o700)
    stack = pathlib.Path(PROJECTS[project][0])
    config_name = 'paeonia' if project == 'paeonia' else 'tidex-convex'
    config = '/srv/backup/' + config_name + '.conf'
    # These files are root-owned shell configuration already sourced by the backup timers.
    values = subprocess.check_output(['bash', '-c', 'source "$1"; printf "%s\\0%s" "$CLI_DIR" "${OFFSITE_REMOTE:-}"', 'backup', config]).decode().split('\0')
    cli, remote = values
    env = os.environ.copy()
    env.update(CONVEX_SELF_HOSTED_URL='http://127.0.0.1:' + str(PORTS[project]),
               CONVEX_SELF_HOSTED_ADMIN_KEY=(stack / 'admin-key').read_text().strip())
    executable = str(pathlib.Path(cli) / 'node_modules/.bin/convex')
    archive = destination / 'export.zip'
    with (destination / 'export.log').open('w') as log:
        subprocess.run([executable, 'export', '--include-file-storage', '--path', str(archive)],
                       cwd=cli, env=env, stdout=log, stderr=log, check=True, timeout=1200)
    file_count = verify_export(archive)
    with (destination / 'convex.env').open('w') as output:
        subprocess.run([executable, 'env', 'list'], cwd=cli, env=env, stdout=output, check=True, timeout=60)
    config_archive = destination / 'config.tar.gz'
    with tarfile.open(config_archive, 'w:gz') as tar:
        for filename in ['.env', 'admin-key', 'docker-compose.yml']:
            tar.add(stack / filename, arcname='stack/' + filename)
        tar.add(destination / 'convex.env', arcname='convex.env')
        tar.add(config, arcname='backup.conf')
        tar.add(SOURCE, arcname='runtime-source', filter=lambda info: None if '__pycache__' in info.name else info)
        tar.add(manifest, arcname='images.json')
    hashes = {p.name: hashlib.file_digest(p.open('rb'), 'sha256').hexdigest() for p in [archive, config_archive]}
    (destination / 'sha256.json').write_text(json.dumps(hashes, indent=2) + '\n')
    if not remote:
        raise RuntimeError('Offsite backup destination is required for an upgrade')
    target = remote + '/convex-upgrades/' + project + '/' + destination.parent.name + '/' + destination.name
    for name in ['export.zip', 'config.tar.gz', 'sha256.json']:
        subprocess.run(['rclone', 'copyto', str(destination / name), target + '/' + name, '--s3-no-check-bucket'], check=True)
        subprocess.run(['rclone', 'check', str(destination), target, '--include', name, '--one-way', '--download', '--s3-no-check-bucket'], check=True)
    print(project, 'full export, config and offsite contents verified; storage files:', file_count, flush=True)
    return hashes


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('project', choices=PROJECTS)
    p.add_argument('--destination', type=pathlib.Path, required=True)
    p.add_argument('--images', type=pathlib.Path, required=True)
    a = p.parse_args()
    os.umask(0o077)
    backup(a.project, a.destination.resolve(), a.images.resolve())


if __name__ == '__main__':
    main()
