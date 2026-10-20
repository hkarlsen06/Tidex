#!/usr/bin/env bun
// Copies Tidex from Supabase on one-s into a Convex deployment and a Clerk instance.
// Phase 1, steps 7 and 8 of docs/convex-migration-plan.md.
//
//   bun scripts/migrate.ts --env-file .env.local --clerk-env <file with CLERK_SECRET_KEY>
//
// The development Clerk instance holds at most 100 users, so dev runs pass
// --clerk-only <uuid,uuid> to give only those accounts a Clerk user, or --skip-clerk.
//
// --env-file picks the Convex deployment (.env.local is the dev deployment on the Mac,
// .env.production is convex.tidex.no). It reads Postgres and Storage over `ssh one-s`
// and never writes to them. It replaces every Convex table and file, so run it only
// before cutover or during it. Reruns are safe: Clerk users are found by external_id
// and updated instead of created again.

import { readFileSync } from "node:fs";
import schema from "../convex/schema";

const args = process.argv.slice(2);
const flag = (name: string) => {
  const i = args.indexOf(name);
  return i === -1 ? undefined : args[i + 1];
};
const ENV_FILE = flag("--env-file") ?? ".env.local";
const CLERK_ENV = flag("--clerk-env");
const SKIP_CLERK = args.includes("--skip-clerk");
const CLERK_ONLY = flag("--clerk-only")?.split(",");
const WORK = `/tmp/tidex-migration-${Date.now()}`;

const log = (...m: unknown[]) => console.log(new Date().toISOString().slice(11, 19), ...m);

// ---------- Reading Postgres and Storage on one-s ----------

const SSH_DB = "cd /srv/tidex/tidex-sb && sudo docker compose exec -T db psql -U postgres -d postgres -At -v ON_ERROR_STOP=1";

async function run(cmd: string[], stdin?: string): Promise<Buffer> {
  const proc = Bun.spawn(cmd, { stdin: stdin === undefined ? "ignore" : new TextEncoder().encode(stdin), stdout: "pipe", stderr: "pipe" });
  const [out, err, code] = await Promise.all([new Response(proc.stdout).arrayBuffer(), new Response(proc.stderr).text(), proc.exited]);
  if (code !== 0) throw new Error(`${cmd.join(" ").slice(0, 80)} failed: ${err.slice(0, 500)}`);
  return Buffer.from(out);
}

/** Runs a query that returns one JSON value per row. */
async function pg(sql: string): Promise<any[]> {
  const out = (await run(["ssh", "-T", "one-s", SSH_DB], sql)).toString();
  return out.split("\n").filter((l) => l.trim() !== "").map((l) => JSON.parse(l));
}

/** A file from Supabase Storage, read from its disk, which works while Caddy blocks /storage/v1. */
async function storageFile(bucket: string, name: string, version: string): Promise<Buffer> {
  const path = `/srv/tidex/tidex-sb/volumes/storage/stub/stub/${bucket}/${name}/${version}`;
  return await run(["ssh", "-T", "one-s", `sudo cat ${JSON.stringify(path)}`]);
}

// ---------- Writing Convex ----------

async function convex(cmdArgs: string[], stdin?: string): Promise<string> {
  return (await run(["bunx", "convex", ...cmdArgs, "--env-file", ENV_FILE], stdin)).toString();
}

async function convexRun(fn: string, fnArgs: object): Promise<any> {
  const out = await convex(["run", fn, JSON.stringify(fnArgs)]);
  return JSON.parse(out.trim() || "null");
}

async function importTable(table: string, rows: object[]) {
  const file = `${WORK}/${table}.jsonl`;
  await Bun.write(file, rows.map((r) => JSON.stringify(r)).join("\n") + (rows.length ? "\n" : ""));
  await convex(["import", "--table", table, "--replace", "-y", file]);
}

/** Uploads files to Convex storage and returns their storage ids, in order. */
async function upload(files: { bytes: Buffer; contentType: string }[]): Promise<string[]> {
  const ids: string[] = [];
  for (let i = 0; i < files.length; i += 50) {
    const batch = files.slice(i, i + 50);
    const urls: string[] = await convexRun("migration:uploadUrls", { count: batch.length });
    for (const [j, f] of batch.entries()) {
      const res = await fetch(urls[j]!, { method: "POST", headers: { "Content-Type": f.contentType }, body: f.bytes });
      if (!res.ok) throw new Error(`Upload failed with ${res.status}`);
      ids.push(((await res.json()) as { storageId: string }).storageId);
    }
  }
  return ids;
}

// ---------- Shaping rows ----------

const fields: Record<string, string[]> = Object.fromEntries(
  Object.entries((schema as any).tables).map(([name, t]: [string, any]) => [name, Object.keys(t.validator.fields)]),
);

const TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/;
let revision = 0;

/**
 * Keeps the schema's fields, leaves out nulls, rewrites timestamps to toISOString()
 * form so they sort as strings, and gives each row a fresh revision. Postgres counted
 * revisions per row, so its values can't be sync cursors.
 */
function shape(table: string, row: Record<string, unknown>, extra: Record<string, unknown> = {}) {
  const out: Record<string, unknown> = {};
  for (const f of fields[table]!) {
    let value = f in extra ? extra[f] : row[f];
    if (value === null || value === undefined) continue;
    if (typeof value === "string" && TIMESTAMP.test(value)) value = new Date(value).toISOString();
    out[f] = value;
  }
  if (fields[table]!.includes("revision")) out.revision = ++revision;
  return out;
}

const all = (schemaTable: string) => `select row_to_json(t) from ${schemaTable} t`;

// ---------- Clerk ----------

const clerkKey = (() => {
  if (SKIP_CLERK) return "";
  if (CLERK_ENV === undefined) throw new Error("Pass --clerk-env <file> or --skip-clerk");
  const key = readFileSync(CLERK_ENV, "utf8").match(/CLERK_SECRET_KEY=(\S+)/)?.[1];
  if (key === undefined) throw new Error(`No CLERK_SECRET_KEY in ${CLERK_ENV}`);
  return key;
})();

let lastClerkCall = 0;
async function clerk(method: string, path: string, body?: object): Promise<any> {
  // Clerk allows 100 Backend API requests per 10 seconds.
  const wait = lastClerkCall + 120 - Date.now();
  if (wait > 0) await Bun.sleep(wait);
  lastClerkCall = Date.now();
  const res = await fetch(`https://api.clerk.com/v1${path}`, {
    method,
    headers: { Authorization: `Bearer ${clerkKey}`, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (res.status === 429) {
    await Bun.sleep(10_000);
    return clerk(method, path, body);
  }
  const data = await res.json();
  if (!res.ok) throw new Error(`Clerk ${method} ${path}: ${res.status} ${JSON.stringify(data).slice(0, 300)}`);
  return data;
}

type AuthUser = {
  id: string;
  email: string | null;
  name: string | null;
  avatar_url: string | null;
  locale: string | null;
  terms_accepted_at: string | null;
  role: string | null;
  banned: boolean;
  last_sign_in_at: string | null;
  created_at: string;
  providers: string[] | null;
  password_hash: string | null;
  proven_emails: string[] | null;
};

/** Creates or updates the user's Clerk user and returns its id, or null without an email. */
async function syncClerkUser(u: AuthUser): Promise<string | null> {
  const emails = u.proven_emails ?? [];
  if (emails.length === 0) return null;
  // The account's own address first, so it becomes the primary one.
  const ordered = [...new Set([u.email, ...emails].filter((e): e is string => e !== null && emails.includes(e)))];
  const password = u.password_hash?.startsWith("$2") ? { password_digest: u.password_hash, password_hasher: "bcrypt" } : {};
  const existing = (await clerk("GET", `/users?external_id=${encodeURIComponent(u.id)}`)) as any[];
  if (existing.length === 0) {
    const created = await clerk("POST", "/users", {
      external_id: u.id,
      email_address: ordered,
      ...password,
      skip_password_checks: true,
      skip_password_requirement: true,
      created_at: u.created_at,
    });
    return created.id;
  }
  const user = existing[0];
  const have = new Set((user.email_addresses as { email_address: string }[]).map((e) => e.email_address.toLowerCase()));
  for (const email of ordered) {
    if (!have.has(email)) await clerk("POST", "/email_addresses", { user_id: user.id, email_address: email, verified: true });
  }
  if (password.password_digest !== undefined) {
    await clerk("PATCH", `/users/${user.id}`, { ...password, skip_password_checks: true });
  }
  return user.id;
}

// ---------- The run ----------

async function main() {
  await run(["mkdir", "-p", WORK]);
  log(`Writing to the deployment in ${ENV_FILE}${SKIP_CLERK ? ", skipping Clerk" : ""}`);
  const expected: Record<string, number> = {};
  const put = async (table: string, rows: object[]) => {
    await importTable(table, rows);
    expected[table] = rows.length;
    log(`${table}: ${rows.length}`);
  };

  // Users and Clerk. Proven emails follow find_user_by_email: a verified email
  // identity, or the email on a Google or Apple identity. Clerk treats imported
  // addresses as verified, so an unconfirmed one must never reach it.
  const authUsers = (await pg(`
    select json_build_object(
      'id', u.id,
      'email', lower(u.email),
      'name', coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name'),
      'avatar_url', coalesce(u.raw_user_meta_data->>'avatar_url', u.raw_user_meta_data->>'picture'),
      'locale', u.raw_user_meta_data->>'locale',
      'terms_accepted_at', u.raw_user_meta_data->>'terms_accepted_at',
      'role', u.raw_app_meta_data->>'role',
      'banned', u.banned_until is not null and u.banned_until > now(),
      'last_sign_in_at', u.last_sign_in_at,
      'created_at', u.created_at,
      'providers', u.raw_app_meta_data->'providers',
      'password_hash', u.encrypted_password,
      'proven_emails', (
        select json_agg(distinct lower(i.identity_data->>'email'))
        from auth.identities i
        where i.user_id = u.id
          and i.identity_data->>'email' like '%@%'
          and (i.provider in ('google', 'apple') or (i.provider = 'email' and i.identity_data->>'email_verified' = 'true'))
      )
    )
    from auth.users u order by u.created_at`)) as AuthUser[];
  const clerkIds = new Map<string, string>();
  if (!SKIP_CLERK) {
    for (const [i, u] of authUsers.entries()) {
      if (CLERK_ONLY !== undefined && !CLERK_ONLY.includes(u.id)) continue;
      const id = await syncClerkUser(u);
      if (id !== null) clerkIds.set(u.id, id);
      if ((i + 1) % 25 === 0) log(`Clerk: ${i + 1} of ${authUsers.length}`);
    }
    log(`Clerk: ${clerkIds.size} users${CLERK_ONLY === undefined ? `, ${authUsers.length - clerkIds.size} without a proven email` : ""}`);
  }
  const now = new Date().toISOString();
  await put(
    "users",
    authUsers.map((u) =>
      shape("users", {}, {
        id: u.id,
        supabase_user_id: u.id,
        clerk_user_id: clerkIds.get(u.id),
        email: u.email,
        name: u.name,
        avatar_url: u.avatar_url,
        locale: u.locale,
        terms_accepted_at: u.terms_accepted_at,
        role: u.role === "admin" ? "admin" : null,
        banned_at: u.banned ? now : null,
        last_sign_in_at: u.last_sign_in_at,
        created_at: u.created_at,
        providers: u.providers,
      }),
    ),
  );
  await put("legacy_identities", await pg(`
    select json_build_object('provider', provider, 'sub', identity_data->>'sub', 'user_id', user_id)
    from auth.identities where provider in ('apple', 'google') and identity_data->>'sub' is not null`));
  await put("legacy_impersonation_sessions", await pg(`
    select json_build_object('auth_session_id', auth_session_id::text)
    from internal.impersonation_sessions where auth_session_id is not null`));

  // Files. A rerun deletes the previous copy's files first.
  let deleted = 0;
  for (let n = 1; n > 0; deleted += n) n = await convexRun("migration:deleteFiles", {});
  if (deleted > 0) log(`Deleted ${deleted} files from an earlier run`);
  const objects = new Map(
    (await pg(`select json_build_object('bucket', bucket_id, 'name', name, 'version', version, 'mime', metadata->>'mimetype') from storage.objects`)).map(
      (o) => [`${o.bucket}/${o.name}`, o] as const,
    ),
  );
  const copyFiles = async (keys: string[]) => {
    const found = keys.map((k) => objects.get(k));
    const missing = keys.filter((_, i) => found[i] === undefined);
    if (missing.length > 0) throw new Error(`Files missing in Storage: ${missing.join(", ")}`);
    const files = [];
    for (const o of found) files.push({ bytes: await storageFile(o.bucket, o.name, o.version), contentType: o.mime ?? "application/octet-stream" });
    return await upload(files);
  };

  // Rows. Each table keeps its Postgres name and columns. The exceptions are noted.
  for (const table of [
    "profiles", "jobs", "user_shifts", "events", "recurring_shifts", "wage_snapshots", "payroll_adjustments",
    "notification_preferences", "shift_shares", "direct_threads", "thread_memberships", "thread_user_state",
    "messages", "message_reactions", "abuse_reports", "subscriptions", "feedback", "onboarding_funnel_steps",
  ]) {
    await put(table, (await pg(all(`public.${table}`))).map((r) => shape(table, r)));
  }
  for (const table of [
    "admin_audit_log", "admin_broadcasts", "app_account_tokens", "app_activity_hours", "user_app_activity",
    "apple_notifications", "apple_orphan_notifications", "auth_diagnostic_events", "calendar_subscription_tokens",
    "impersonation_audit_log", "live_activity_deliveries", "onboarding_preauth_steps", "paywall_config",
    "tariff_types", "tariff_versions",
  ]) {
    await put(table, (await pg(all(`internal.${table}`))).map((r) => shape(table, r)));
  }
  // Devices with only an FCM token were last seen in January 2026. Convex sends APNs only.
  await put("push_devices", (await pg(`${all("internal.push_devices")} where apns_token is not null`)).map((r) => shape("push_devices", r)));
  // Pending pushes would go out late after cutover. History stays for the admin screens.
  await put(
    "notifications_outbox",
    (await pg(`${all("internal.notifications_outbox")} where status in ('sent', 'failed', 'skipped')`)).map((r) => shape("notifications_outbox", r)),
  );

  const threads = await pg(all("public.threads"));
  const avatarIds = await copyFiles(threads.filter((t) => t.avatar_url).map((t) => storageKey(t.avatar_url)));
  let avatarIndex = 0;
  await put("threads", threads.map((t) => shape("threads", t, { avatar_storage_id: t.avatar_url ? avatarIds[avatarIndex++] : null })));

  const attachments = await pg(all("public.message_attachments"));
  const attachmentIds = await copyFiles(attachments.map((a) => `${a.storage_bucket}/${a.storage_path}`));
  await put("message_attachments", attachments.map((a, i) => shape("message_attachments", a, { storage_id: attachmentIds[i] })));
  log(`Copied ${attachmentIds.length} message images`);

  const settings = await pg(all("public.user_settings"));
  const pictured = settings.filter((s) => s.profile_picture_url);
  const pictureIds = await copyFiles(pictured.map((s) => storageKey(s.profile_picture_url)));
  const pictureFor = new Map(pictured.map((s, i) => [s.user_id, pictureIds[i]]));
  await put("user_settings", settings.map((s) => shape("user_settings", s, { profile_picture_storage_id: pictureFor.get(s.user_id) ?? null })));
  log(`Copied ${pictureIds.length} profile pictures`);

  // Tables that start empty in Convex.
  for (const table of ["impersonation_sessions", "clerk_user_aliases", "typing_indicators", "attachment_uploads"]) await put(table, []);
  await importTable("revision_counter", [{ value: revision }]);
  log(`revision_counter: ${revision}`);

  // Counts.
  let mismatches = 0;
  for (const [table, n] of Object.entries(expected)) {
    const got = await convexRun("migration:count", { table });
    if (got !== n) {
      mismatches += 1;
      log(`MISMATCH ${table}: expected ${n}, Convex has ${got}`);
    }
  }
  const missingTables = Object.keys(fields).filter((t) => !(t in expected) && t !== "revision_counter");
  if (missingTables.length > 0) log(`Tables the script didn't write: ${missingTables.join(", ")}`);
  log(mismatches === 0 && missingTables.length === 0 ? "All counts match" : `${mismatches} count mismatches`);
  if (mismatches > 0 || missingTables.length > 0) process.exit(1);
}

/** "bucket/path" from a Supabase Storage URL like .../storage/v1/object/public/<bucket>/<path>?t=... */
function storageKey(url: string): string {
  const match = new URL(url).pathname.match(/\/storage\/v1\/object\/(?:public|authenticated|sign)\/(.+)$/);
  if (match === null) throw new Error(`Not a Storage URL: ${url}`);
  return decodeURIComponent(match[1]!);
}

await main();
