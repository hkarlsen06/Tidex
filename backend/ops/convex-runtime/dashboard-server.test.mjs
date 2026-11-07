import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { once } from 'node:events';

test('the released dashboard can be served without exposing credentials or filesystem paths', async (t) => {
  const root = await mkdtemp(join(tmpdir(), 'convex-dashboard-test-'));
  await mkdir(join(root, '_next/static'), { recursive: true });
  const html = '<script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{}}}</script>';
  await writeFile(join(root, 'index.html'), html);
  await writeFile(join(root, 'settings.html'), html);
  await writeFile(join(root, '_next/static/test.js'), 'window.dashboardReady = true;');
  process.env.DASHBOARD_ROOT = root;
  process.env.PORT = '0';
  process.env.NEXT_PUBLIC_DEPLOYMENT_URL = 'https://api.example.test/';
  process.env.NEXT_PUBLIC_ADMIN_KEY = 'credential-must-not-be-served';
  const { server } = await import('./dashboard-server.mjs');
  if (!server.listening) await once(server, 'listening');
  t.after(async () => {
    await new Promise((resolve) => server.close(resolve));
    await rm(root, { recursive: true });
  });
  const base = `http://127.0.0.1:${server.address().port}`;

  const page = await fetch(base);
  assert.equal(page.status, 200);
  assert.equal(page.headers.get('cache-control'), 'no-store');
  assert.equal(page.headers.get('x-content-type-options'), 'nosniff');
  const body = await page.text();
  assert.ok(body.includes('https://api.example.test'));
  assert.ok(!body.includes(process.env.NEXT_PUBLIC_ADMIN_KEY));

  const asset = await fetch(base + '/_next/static/test.js');
  assert.equal(asset.status, 200);
  assert.equal(asset.headers.get('content-type'), 'application/javascript; charset=utf-8');
  assert.ok(asset.headers.get('cache-control').includes('immutable'));
  assert.equal(await asset.text(), 'window.dashboardReady = true;');
  const head = await fetch(base + '/settings', { method: 'HEAD' });
  assert.equal(head.status, 200);
  assert.equal(await head.text(), '');
  assert.equal((await fetch(base + '/settings/', { redirect: 'manual' })).status, 308);

  for (const path of ['/..%2f..%2fetc%2fpasswd', '/%00', '/%E0%A4%A']) {
    assert.equal((await fetch(base + path)).status, 400);
  }
  assert.equal((await fetch(base, { method: 'POST', body: 'rejected' })).status, 405);
  assert.equal((await fetch(base + '/api/current_deployment')).status, 404);
  assert.equal((await fetch(base + '/missing-file')).status, 404);
});
