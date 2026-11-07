#!/usr/bin/env python3
"""Gate one app, cold-checkpoint its data, replace pinned images, verify, then reopen traffic."""
import argparse
import copy
import contextlib
import fcntl
import http.server
import json
import os
import pathlib
import re
import shutil
import sqlite3
import subprocess
import threading
import time
import urllib.request
from backup import backup
from rehearse import PROJECTS
from verify import PORTS, verify

GATES = {'paeonia': {'127.0.0.1:3210': '127.0.0.1:33320', '127.0.0.1:3211': '127.0.0.1:33321'},
         'tidex': {'127.0.0.1:3220': '127.0.0.1:33322', '127.0.0.1:3221': '127.0.0.1:33323'}}
ROOT = pathlib.Path('/srv/convex-runtime/checkpoints')


@contextlib.contextmanager
def upgrade_lock():
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (ROOT / 'upgrade.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield


def object_storage(checkpoint, environment, restore=False):
    """Copy all persisted S3 objects while stopped; recovery never deletes extra objects."""
    buckets = {k: v for k, v in environment.items() if k.startswith('S3_STORAGE_') and k.endswith('_BUCKET')}
    if not buckets:
        return
    env = os.environ.copy()
    settings = {'TYPE': 's3', 'PROVIDER': 'Cloudflare', 'ACCESS_KEY_ID': environment['AWS_ACCESS_KEY_ID'],
                'SECRET_ACCESS_KEY': environment['AWS_SECRET_ACCESS_KEY'], 'ENDPOINT': environment['S3_ENDPOINT_URL'],
                'REGION': environment.get('AWS_REGION', 'auto'), 'FORCE_PATH_STYLE': 'true'}
    env.update({'RCLONE_CONFIG_CHECKPOINT_' + key: value for key, value in settings.items()})
    with (checkpoint / ('object-restore.log' if restore else 'object-snapshot.log')).open('w') as log:
        for bucket in sorted(set(buckets.values())):
            local = checkpoint / 'objects' / bucket
            remote = 'checkpoint:' + bucket
            if not restore:
                local.mkdir(parents=True, exist_ok=False)
            elif not local.is_dir():
                raise RuntimeError('Missing cold object snapshot: ' + bucket)
            source, target = (str(local), remote) if restore else (remote, str(local))
            # Recovery must replace checkpoint objects even when cached metadata looks unchanged.
            force = ['--ignore-times'] if restore else []
            subprocess.run(['rclone', 'copy', source, target, '--transfers', '2', '--s3-no-check-bucket', *force],
                           env=env, stdout=log, stderr=log, check=True, timeout=1800)
            subprocess.run(['rclone', 'check', source, target, '--one-way', '--download', '--s3-no-check-bucket'],
                           env=env, stdout=log, stderr=log, check=True, timeout=1800)
    print('Cold object storage ' + ('restored' if restore else 'checkpointed') + ' and contents verified', flush=True)


def replace_upstreams(config, replacements):
    """Transform only Caddy reverse-proxy dial fields, preserving all other routes."""
    result = copy.deepcopy(config)
    counts = dict.fromkeys(replacements, 0)

    def walk(value):
        if isinstance(value, dict):
            if value.get('handler') == 'reverse_proxy':
                for upstream in value.get('upstreams', []):
                    dial = upstream.get('dial')
                    if dial in replacements:
                        upstream['dial'] = replacements[dial]
                        counts[dial] += 1
            for child in value.values():
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)
    walk(result)
    return result, counts


def caddy_config():
    with urllib.request.urlopen('http://127.0.0.1:2019/config/', timeout=10) as response:
        return json.load(response)


def gate(project, close):
    mapping = GATES[project] if close else {v: k for k, v in GATES[project].items()}
    config, counts = replace_upstreams(caddy_config(), mapping)
    if close and not all(counts.values()):
        raise RuntimeError('Expected Caddy upstream missing; configuration was not changed')
    if not any(counts.values()):
        return
    request = urllib.request.Request('http://127.0.0.1:2019/load', data=json.dumps(config).encode(),
                                     headers={'Content-Type': 'application/json'}, method='POST')
    with urllib.request.urlopen(request, timeout=15) as response:
        if response.status != 200:
            raise RuntimeError('Caddy gate change failed')
    # A fresh read catches a rejected or overwritten config before touching the database.
    _, remaining = replace_upstreams(caddy_config(), mapping)
    if any(remaining.values()):
        raise RuntimeError('Caddy upstream change did not persist')


class Maintenance(http.server.BaseHTTPRequestHandler):
    def reply(self):
        self.send_response(503)
        self.send_header('Retry-After', '60')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', '0')
        self.end_headers()
    do_GET = do_HEAD = do_POST = do_PUT = do_PATCH = do_DELETE = do_OPTIONS = reply

    def log_message(self, *_args):
        pass


def compose(project, *args):
    stack = pathlib.Path(PROJECTS[project][0])
    name = 'convex' if project == 'paeonia' else 'tidex-convex'
    subprocess.run(['docker', 'compose', '-p', name, '-f', str(stack / 'docker-compose.yml'), *args],
                   cwd=stack, check=True, timeout=180)


def wait_ready(project):
    url = 'http://127.0.0.1:' + str(PORTS[project])
    for _ in range(120):
        try:
            with urllib.request.urlopen(url + '/version', timeout=1) as response:
                if response.status == 200:
                    return
        except OSError:
            time.sleep(1)
    raise RuntimeError('Backend readiness deadline exceeded')


def dashboard(project):
    port = 6791 if project == 'paeonia' else 6792
    base = 'http://127.0.0.1:' + str(port)
    with urllib.request.urlopen(base, timeout=10) as response:
        html = response.read().decode()
        assert response.status == 200
        assert ('https://api.paeonia.no' if project == 'paeonia' else 'https://convex.tidex.no') in html
    assets = re.findall(r'(?:src|href)="(/_next/static/[^"?]+)', html)
    assert assets, 'Dashboard has no executable assets'
    for path in assets:
        with urllib.request.urlopen(base + path, timeout=10) as response:
            assert response.status == 200 and response.read(), 'Dashboard asset is unavailable'
    return {'html': True, 'assets': len(assets)}


def image_compose(text, images):
    def replacement(match):
        kind = match.group(2)
        return match.group(1) + images[kind]['image']
    pattern = r'(    image: )(?:ghcr\.io/convex/convex-|convex-runtime/)(backend|dashboard)@sha256:[0-9a-f]{64}'
    result, count = re.subn(pattern, replacement, text)
    if count != 2:
        raise RuntimeError('Expected exactly two pinned upstream image lines')
    # Allow ongoing upgrades from our own immutable images as well.
    return result


def apply(project, images_path):
    manifest = json.loads(images_path.read_text())
    stamp = time.strftime('%Y%m%d-%H%M%S', time.gmtime()) + '-' + project
    checkpoint = ROOT / stamp
    checkpoint.mkdir(mode=0o700)
    (checkpoint / 'images.json').write_text(json.dumps(manifest, indent=2))
    stack = pathlib.Path(PROJECTS[project][0])
    compose_path = stack / 'docker-compose.yml'
    original = compose_path.read_text()
    info = json.loads(subprocess.check_output(['docker', 'inspect', PROJECTS[project][1]]))[0]
    environment = dict(value.split('=', 1) for value in info['Config']['Env'] if '=' in value)
    updated = image_compose(original, manifest['images'])
    timers = ['paeonia-backup.timer', 'paeonia-backup-hourly.timer'] if project == 'paeonia' else ['tidex-convex-backup.timer', 'tidex-convex-backup-hourly.timer']
    active = [timer for timer in timers if subprocess.run(['systemctl', 'is-active', '--quiet', timer]).returncode == 0]
    state = {'project': project, 'checkpoint': str(checkpoint), 'gated': False, 'cold_snapshot': False,
             'backend_stopped': False, 'images_changed': False, 'validated': False, 'timers': active}

    def save():
        temporary = checkpoint / 'state.tmp'
        temporary.write_text(json.dumps(state, indent=2) + '\n')
        temporary.replace(checkpoint / 'state.json')
    save()
    # An offsite backup failure occurs before maintenance begins.
    backup(project, checkpoint / 'before', images_path)
    servers = []
    safe_to_reopen = True
    try:
        for address in GATES[project].values():
            host, port = address.split(':')
            server = http.server.ThreadingHTTPServer((host, int(port)), Maintenance)
            servers.append(server)
            threading.Thread(target=server.serve_forever, daemon=True).start()
        (checkpoint / 'caddy-before.json').write_text(json.dumps(caddy_config()))
        # Mark the intent first so a failed POST response still triggers restoration.
        state['gated'] = True
        save()
        gate(project, True)
        if active:
            subprocess.run(['systemctl', 'stop', *active], check=True)
        for timer in timers:
            service = timer.replace('.timer', '.service')
            if subprocess.run(['systemctl', 'is-active', '--quiet', service]).returncode == 0:
                raise RuntimeError('A backup is still running; retry after it finishes')
        baseline = verify(project, manifest, identity=False)
        (checkpoint / 'baseline.json').write_text(json.dumps(baseline))
        (checkpoint / 'docker-compose.yml').write_text(original)
        # Set the flag before stopping, so an interrupted stop still restarts the old backend.
        state['backend_stopped'] = True
        save()
        compose(project, 'stop', '-t', '90', 'backend')
        # Node executor Unix sockets are ephemeral and cannot be copied as regular files.
        shutil.copytree(stack / 'data', checkpoint / 'data',
                        ignore=lambda directory, names: ['tmp'] if pathlib.Path(directory) == stack / 'data' else [])
        databases = list((checkpoint / 'data').glob('*.sqlite3'))
        assert databases, 'No SQLite database found in the cold snapshot'
        for database in databases:
            with sqlite3.connect(database) as connection:
                assert connection.execute('PRAGMA integrity_check').fetchone() == ('ok',)
        object_storage(checkpoint, environment)
        state['cold_snapshot'] = True
        save()
        # This assignment precedes the write, including failures during replacement/startup.
        state['images_changed'] = True
        save()
        compose_path.write_text(updated)
        compose(project, 'up', '-d', '--pull', 'never', 'backend', 'dashboard')
        wait_ready(project)
        result = verify(project, manifest)
        assert result['counts'] == baseline['counts'], 'Application row counts changed across the engine upgrade'
        assert result['read_hashes'] == baseline['read_hashes'], 'Application reads changed across the engine upgrade'
        result['dashboard'] = dashboard(project)
        (checkpoint / 'verified.json').write_text(json.dumps(result, indent=2))
        state['validated'] = True
        save()
        print(project, 'new runtime, application reads, real JWT and dashboard verified', flush=True)
    except BaseException:
        if state['backend_stopped']:
            safe_to_reopen = False
            if state['images_changed']:
                compose(project, 'stop', '-t', '90', 'backend', 'dashboard')
                if not state['cold_snapshot']:
                    raise RuntimeError('Images changed without a complete snapshot; traffic remains gated')
                (stack / 'data').rename(checkpoint / 'failed-data')
                shutil.copytree(checkpoint / 'data', stack / 'data')
                object_storage(checkpoint, environment, restore=True)
                compose_path.write_text(original)
            compose(project, 'up', '-d', '--pull', 'never', 'backend', 'dashboard')
            wait_ready(project)
            restored = verify(project, manifest, identity=False)
            assert restored['counts'] == baseline['counts'], 'Rollback counts differ'
            state['rolled_back'] = True
            safe_to_reopen = True
            save()
            print(project, 'old runtime and checkpoint restored', flush=True)
        raise
    finally:
        if state['gated'] and safe_to_reopen:
            gate(project, False)
            state['gated'] = False
            save()
        for server in servers:
            server.shutdown()
            server.server_close()
        if active and safe_to_reopen:
            subprocess.run(['systemctl', 'start', *active], check=True)
    # Traffic is open now. Never restore the cold snapshot after accepting new writes.
    backup(project, checkpoint / 'after', images_path)
    state['complete'] = True
    save()
    print(project, 'upgrade complete:', checkpoint, flush=True)


def recover(project, checkpoint):
    checkpoint = checkpoint.resolve()
    if checkpoint.parent != ROOT.resolve():
        raise RuntimeError('Recovery must name a checkpoint under ' + str(ROOT))
    state = json.loads((checkpoint / 'state.json').read_text())
    if state['project'] != project or not state['gated']:
        raise RuntimeError('Checkpoint does not describe this app in maintenance')
    if not (state['validated'] or state.get('rolled_back')):
        raise RuntimeError('Runtime was never validated. Restore its cold data, objects and compose first; record rolled_back only after verification.')
    manifest = json.loads((checkpoint / 'images.json').read_text())
    wait_ready(project)
    result = verify(project, manifest, identity=not state.get('rolled_back'))
    baseline = json.loads((checkpoint / 'baseline.json').read_text())
    if state.get('rolled_back') and result['image'] != baseline['image']:
        raise RuntimeError('Recovery runtime does not match the saved original image')
    if result['counts'] != baseline['counts'] or result['read_hashes'] != baseline['read_hashes']:
        raise RuntimeError('Recovery application data differs from its checkpoint')
    dashboard(project)
    gate(project, False)
    state['gated'] = False
    (checkpoint / 'state.json').write_text(json.dumps(state, indent=2))
    if state['timers']:
        subprocess.run(['systemctl', 'start', *state['timers']], check=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('project', choices=PROJECTS)
    p.add_argument('--images', type=pathlib.Path)
    p.add_argument('--recover-checkpoint', type=pathlib.Path, help='Recovery only: revalidate a previously verified checkpoint before reopening traffic')
    a = p.parse_args()
    os.umask(0o077)
    with upgrade_lock():
        if a.recover_checkpoint:
            recover(a.project, a.recover_checkpoint)
        else:
            if not a.images:
                p.error('--images is required')
            apply(a.project, a.images.resolve())


if __name__ == '__main__':
    main()
