const { readFileSync } = require('node:fs');
const { createRequire } = require('node:module');
const { randomUUID } = require('node:crypto');
const installed = createRequire('/srv/paeonia/cli/package.json');
const { BaseConvexClient } = installed('convex/browser');

async function main() {
  const input = JSON.parse(readFileSync(0, 'utf8'));
  let token;
  let current;
  let failure;
  const client = new BaseConvexClient(input.url, (updates) => {
    if (!updates.includes(token)) return;
    try { current = client.localQueryResultByToken(token); } catch (error) { failure = error; }
  }, { logger: false, webSocketConstructor: WebSocket });
  if (input.jwt) client.setAuth(async () => input.jwt, () => {});
  else client.setAdminAuth(input.key, input.identity);
  const path = input.project === 'tidex' ? 'sync:revisions' : 'identity:get_notification_preferences';
  token = client.subscribe(path, {}).queryToken;
  const waitFor = async (predicate) => {
    const deadline = Date.now() + 15000;
    while (!predicate()) {
      if (failure) throw failure;
      if (Date.now() > deadline) throw new Error('Subscription timed out');
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
  };
  const mutate = async (path, args) => {
    const actingAs = Buffer.from(JSON.stringify(input.identity)).toString('base64');
    const response = await fetch((input.mutationUrl ?? input.url) + '/api/mutation', {
      method: 'POST', headers: { Authorization: `Convex ${input.key}:${actingAs}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ path, args, format: 'json' }), signal: AbortSignal.timeout(15000),
    });
    const result = await response.json();
    if (result.status !== 'success') throw new Error('Subscription test mutation failed');
    return result.value;
  };
  try {
    await waitFor(() => current !== undefined);
    if (input.readOnly) {
      console.log(JSON.stringify({ initial_received: true, mutation_observed: false }));
      return;
    }
    if (input.project === 'tidex') {
      const row = { id: randomUUID(), name: 'Subscription verification', is_default: false, sort_order: 999, currency: 'kr' };
      const created = await mutate('jobs:insert', { row, expected_user_id: input.userId });
      if (created.status !== 'ok') throw new Error('Job insert failed');
      try {
        await waitFor(() => current.jobs >= created.row.revision);
      } finally {
        const removed = await mutate('jobs:remove', { id: row.id, expected_revision: created.row.revision, expected_user_id: input.userId });
        if (removed.status !== 'ok') throw new Error('Temporary job cleanup failed');
      }
    } else {
      const original = current.lock_screen_detail_level;
      const changed = original === 'private' ? 'descriptive' : 'private';
      try {
        await mutate('identity:set_lock_screen_detail_level', { p_level: changed });
        await waitFor(() => current.lock_screen_detail_level === changed);
      } finally {
        const restored = await mutate('identity:set_lock_screen_detail_level', { p_level: original });
        if (restored.lock_screen_detail_level !== original) throw new Error('Preference restoration failed');
        await waitFor(() => current.lock_screen_detail_level === original);
      }
    }
    console.log(JSON.stringify({ initial_received: true, mutation_observed: true }));
  } finally {
    await client.close();
  }
}
main().catch(() => { console.error('WebSocket subscription verification failed'); process.exitCode = 1; });
