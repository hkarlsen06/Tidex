#!/usr/bin/env python3
"""Build pinned official Convex release artifacts with an optional jemalloc layer."""
import argparse
import hashlib
import json
import pathlib
import platform
import shutil
import stat
import subprocess
import urllib.request
import zipfile

SOURCE = pathlib.Path(__file__).resolve().parent


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def download(asset, path):
    if not path.exists():
        temporary = path.with_suffix(path.suffix + '.part')
        with urllib.request.urlopen(asset['url'], timeout=60) as response, temporary.open('wb') as stream:
            shutil.copyfileobj(response, stream)
        temporary.replace(path)
    if sha256(path) != asset['sha256']:
        raise RuntimeError('Checksum mismatch: ' + path.name)


def extract(archive, destination):
    destination.mkdir(exist_ok=True)
    with zipfile.ZipFile(archive) as zipped:
        for member in zipped.infolist():
            name = pathlib.PurePosixPath(member.filename)
            if name.is_absolute() or '..' in name.parts or stat.S_ISLNK(member.external_attr >> 16):
                raise RuntimeError('Unsafe release archive member')
            target = destination.joinpath(*name.parts)
            if member.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with zipped.open(member) as source, target.open('wb') as output:
                    shutil.copyfileobj(source, output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=pathlib.Path, required=True)
    parser.add_argument('--arch', choices=['amd64', 'arm64'], default={'x86_64': 'amd64', 'arm64': 'arm64', 'aarch64': 'arm64'}.get(platform.machine()))
    args = parser.parse_args()
    if args.arch is None:
        parser.error('Specify --arch for this machine')
    lock = json.loads((SOURCE / 'release.json').read_text())
    short = lock['revision'][:7]
    directory = args.directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    assets = lock['assets']
    binary = {'amd64': 'x86_64', 'arm64': 'aarch64'}[args.arch]
    backend_asset = assets[f'convex-local-backend-{binary}-unknown-linux-gnu.zip']
    download(backend_asset, directory / 'backend.zip')
    download(assets['dashboard.zip'], directory / 'dashboard.zip')
    download(assets['LICENSE.md'], directory / 'LICENSE.md')
    download(lock['jemalloc'][args.arch], directory / 'jemalloc.deb')
    for name, asset in lock['scripts'].items():
        download(asset, directory / name)
    with zipfile.ZipFile(directory / 'backend.zip') as archive:
        if archive.namelist() != ['convex-local-backend']:
            raise RuntimeError('Unexpected backend release contents')
    extract(directory / 'backend.zip', directory)
    extract(directory / 'dashboard.zip', directory / 'dashboard')
    for name in ['Dockerfile.backend', 'Dockerfile.dashboard', 'dashboard-server.mjs']:
        shutil.copyfile(SOURCE / name, directory / name)
    (directory / '.dockerignore').write_text('*.zip\n*.part\nimages.json\n')
    binary_sha = sha256(directory / 'convex-local-backend')
    images = {}
    for kind, dockerfile, target in [('stock', 'backend', 'stock'), ('backend', 'backend', 'jemalloc'), ('dashboard', 'dashboard', None)]:
        tag = f'convex-runtime/{kind}:{short}-{args.arch}-r1'
        command = ['docker', 'build', '--platform', 'linux/' + args.arch, '--file', str(directory / ('Dockerfile.' + dockerfile)), '--tag', tag,
                   '--build-arg', 'BASE_IMAGE=' + lock['base_image'], '--build-arg', 'REVISION=' + lock['revision'],
                   '--build-arg', 'BACKEND_SHA256=' + binary_sha, '--build-arg', 'JEMALLOC_SHA256=' + lock['jemalloc'][args.arch]['sha256']]
        if target:
            command += ['--target', target]
        subprocess.run(command + [str(directory)], check=True)
        info = json.loads(subprocess.check_output(['docker', 'image', 'inspect', tag], text=True))[0]
        digest = next(value for value in info['RepoDigests'] if value.endswith('@' + info['Id']))
        images[kind] = {'tag': tag, 'image': digest}
    manifest = {'prerelease': lock['prerelease'], 'published_at': lock['published_at'], 'release': lock['release'], 'revision': lock['revision'], 'arch': args.arch, 'backend_sha256': binary_sha, 'images': images}
    (directory / 'images.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest), flush=True)


if __name__ == '__main__':
    main()
