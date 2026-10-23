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
// and updated instead of created again, and their addresses are set to the proven ones.
//
// Without --clerk-only, a rerun also deletes the Clerk users whose external_id names a
// Supabase user that no longer exists. It stops before deleting anything when more than
// 20 would go, unless --allow-clerk-deletes <n> allows that many. Clerk users without an
// external_id signed up on N+1, and the script never touches them.

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
const ALLOW_CLERK_DELETES = Number(flag("--allow-clerk-deletes") ?? 20);
if (!Number.isInteger(ALLOW_CLERK_DELETES) || ALLOW_CLERK_DELETES < 0) {
  throw new Error("--allow-clerk-deletes takes a whole number");
}
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

/** Quotes a string as one literal word for a POSIX shell. Double quotes would still expand $(...). */
const shellQuote = (s: string) => "'" + s.replaceAll("'", "'\\''") + "'";

/**
 * A file from Supabase Storage, read from its disk, which works while Caddy blocks /storage/v1.
 * Object names come from users, so the path is quoted for the remote shell and may not climb
 * out of the storage folder.
 */
async function storageFile(bucket: string, name: string, version: string): Promise<Buffer> {
  const path = `/srv/tidex/tidex-sb/volumes/storage/stub/stub/${bucket}/${name}/${version}`;
  if (path.split("/").includes("..")) throw new Error(`Refusing a Storage path with "..": ${path}`);
  return await run(["ssh", "-T", "one-s", `sudo cat -- ${shellQuote(path)}`]);
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
  if (!res.ok) {
    const error = new Error(`Clerk ${method} ${path}: ${res.status} ${JSON.stringify(data).slice(0, 300)}`);
    throw Object.assign(error, { status: res.status });
  }
  return data;
}

/** True when Clerk answered with a 4xx, such as an address another Clerk user still holds. */
const clerkRefused = (error: unknown) => {
  const status = (error as { status?: number }).status;
  return status !== undefined && status >= 400 && status < 500;
};

type ClerkEmail = {
  id: string;
  email_address: string;
  verification: { status: string } | null;
  /** The Google or Apple sign-ins (type oauth_<provider>) that use this address. */
  linked_to: { type: string; id: string }[];
};
type ClerkUser = {
  id: string;
  external_id: string | null;
  primary_email_address_id: string | null;
  email_addresses: ClerkEmail[];
};

/** Every Clerk user, oldest first. */
async function allClerkUsers(): Promise<ClerkUser[]> {
  const users: ClerkUser[] = [];
  for (let offset = 0; ; offset += 500) {
    const page = (await clerk("GET", `/users?limit=500&offset=${offset}&order_by=%2Bcreated_at`)) as ClerkUser[];
    users.push(...page);
    if (page.length < 500) return users;
  }
}

/**
 * Deletes the Clerk users of Supabase accounts deleted since an earlier run. Their
 * addresses would block a new owner, and their data would outlive the account deletion.
 * Runs before any address is added, so a freed address can go to its new owner.
 */
async function deleteStaleClerkUsers(supabaseIds: ReadonlySet<string>) {
  const stale = (await allClerkUsers()).filter((c) => c.external_id !== null && !supabaseIds.has(c.external_id));
  const describe = (c: ClerkUser) =>
    `${c.id} (external_id ${c.external_id}, ${c.email_addresses.map((e) => e.email_address).join(", ") || "no email"})`;
  if (stale.length > ALLOW_CLERK_DELETES) {
    for (const c of stale) log(`Would delete Clerk user ${describe(c)}`);
    throw new Error(
      `${stale.length} Clerk users have no Supabase account, more than the ${ALLOW_CLERK_DELETES} allowed. ` +
        `Nothing was deleted. Pass --allow-clerk-deletes ${stale.length} if that is right.`,
    );
  }
  for (const c of stale) {
    await clerk("DELETE", `/users/${c.id}`);
    log(`Deleted Clerk user ${describe(c)}`);
  }
}

type AuthUser = {
  id: string;
  email: string | null;
  name: string | null;
  avatar_url: string | null;
  locale: string | null;
  terms_accepted_at: string | null;
  finished_onboarding: boolean | null;
  role: string | null;
  banned: boolean;
  last_sign_in_at: string | null;
  created_at: string;
  providers: string[] | null;
  password_hash: string | null;
  proven_emails: string[] | null;
};

/**
 * Creates or updates the user's Clerk user and returns its id, or null without an email.
 * An existing Clerk user ends up with exactly the proven addresses, all verified, and the
 * account's own address as primary. Addresses Clerk links to a Google or Apple sign-in stay.
 */
async function syncClerkUser(u: AuthUser): Promise<string | null> {
  const emails = u.proven_emails ?? [];
  const existing = (await clerk("GET", `/users?external_id=${encodeURIComponent(u.id)}`)) as ClerkUser[];
  if (emails.length === 0) {
    if (existing.length > 0) log(`Clerk user ${existing[0]!.id} of ${u.id} has no proven email left. Left as it is.`);
    return null;
  }
  // The account's own address first, so it becomes the primary one.
  const ordered = [...new Set([u.email, ...emails].filter((e): e is string => e !== null && emails.includes(e)))];
  const password = u.password_hash?.startsWith("$2") ? { password_digest: u.password_hash, password_hasher: "bcrypt" } : {};
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
  const user = existing[0]!;
  const have = new Map(user.email_addresses.map((e) => [e.email_address.toLowerCase(), e]));
  for (const email of ordered) {
    const e = have.get(email);
    if (e === undefined) {
      have.set(email, await clerk("POST", "/email_addresses", { user_id: user.id, email_address: email, verified: true }));
    } else if (e.verification?.status !== "verified") {
      await clerk("PATCH", `/email_addresses/${e.id}`, { verified: true });
    }
  }
  // Clerk wants a verified address of the user as primary, and the old primary can only go after.
  const primaryId = have.get(ordered[0]!)!.id;
  if (user.primary_email_address_id !== primaryId) {
    await clerk("PATCH", `/users/${user.id}`, { primary_email_address_id: primaryId });
  }
  for (const e of user.email_addresses) {
    if (emails.includes(e.email_address.toLowerCase()) || e.id === primaryId) continue;
    if (e.linked_to.length > 0) {
      log(`Clerk user ${user.id} keeps ${e.email_address}, which ${e.linked_to.map((l) => l.type).join(", ")} uses`);
      continue;
    }
    await clerk("DELETE", `/email_addresses/${e.id}`);
    log(`Removed ${e.email_address} from Clerk user ${user.id}`);
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
  // identity, or the email on a Google or Apple identity. The account's email
  // counts too once GoTrue confirmed it, because many email identities still say
  // email_verified false after the confirmation. Clerk treats imported addresses
  // as verified, so an unconfirmed one must never reach it.
  const authUsers = (await pg(`
    select json_build_object(
      'id', u.id,
      'email', lower(u.email),
      'name', coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name'),
      'avatar_url', coalesce(u.raw_user_meta_data->>'avatar_url', u.raw_user_meta_data->>'picture'),
      'locale', u.raw_user_meta_data->>'locale',
      'terms_accepted_at', u.raw_user_meta_data->>'terms_accepted_at',
      'finished_onboarding', case when u.raw_user_meta_data->>'finishedOnboarding' = 'true' then true end,
      'role', u.raw_app_meta_data->>'role',
      'banned', u.banned_until is not null and u.banned_until > now(),
      'last_sign_in_at', u.last_sign_in_at,
      'created_at', u.created_at,
      'providers', u.raw_app_meta_data->'providers',
      'password_hash', u.encrypted_password,
      'proven_emails', (
        select json_agg(distinct e) from (
          select lower(i.identity_data->>'email') as e
          from auth.identities i
          where i.user_id = u.id
            and i.identity_data->>'email' like '%@%'
            and (i.provider in ('google', 'apple') or (i.provider = 'email' and i.identity_data->>'email_verified' = 'true'))
          union all
          select lower(u.email) where u.email_confirmed_at is not null and u.email like '%@%'
        ) proven
      )
    )
    from auth.users u order by u.created_at`)) as AuthUser[];
  const clerkIds = new Map<string, string>();
  if (!SKIP_CLERK) {
    if (CLERK_ONLY === undefined) await deleteStaleClerkUsers(new Set(authUsers.map((u) => u.id)));
    else log("Clerk: --clerk-only, so Clerk users of deleted accounts stay");
    // An address can move between two accounts, and Clerk refuses it while the other
    // Clerk user still holds it. Those users go again once every other one is done.
    const retry: AuthUser[] = [];
    for (const [i, u] of authUsers.entries()) {
      if (CLERK_ONLY !== undefined && !CLERK_ONLY.includes(u.id)) continue;
      try {
        const id = await syncClerkUser(u);
        if (id !== null) clerkIds.set(u.id, id);
      } catch (error) {
        if (!clerkRefused(error)) throw error;
        log(`Clerk refused a change for ${u.id}, trying again at the end: ${(error as Error).message}`);
        retry.push(u);
      }
      if ((i + 1) % 25 === 0) log(`Clerk: ${i + 1} of ${authUsers.length}`);
    }
    for (const u of retry) {
      const id = await syncClerkUser(u);
      if (id !== null) clerkIds.set(u.id, id);
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
        finished_onboarding: u.finished_onboarding,
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
    "messages", "message_reactions", "abuse_reports", "feedback", "onboarding_funnel_steps",
  ]) {
    await put(table, (await pg(all(`public.${table}`))).map((r) => shape(table, r)));
  }
  for (const table of [
    "admin_audit_log", "admin_broadcasts", "app_activity_hours", "user_app_activity", "auth_diagnostic_events",
    "calendar_subscription_tokens", "impersonation_audit_log", "live_activity_deliveries", "onboarding_preauth_steps",
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
  for (const table of ["impersonation_sessions", "clerk_user_aliases", "typing_indicators", "attachment_uploads", "account_deletions"]) await put(table, []);
  await importTable("revision_counter", [{ value: revision }]);
  log(`revision_counter: ${revision}`);

  // Counts.
  let mismatches = 0;
  for (const [table, n] of Object.entries(expected)) {
    let got = 0;
    for (let cursor: string | null = null, done = false; !done; ) {
      const page: { n: number; cursor: string; done: boolean } = await convexRun("migration:count", { table, cursor });
      got += page.n;
      ({ cursor, done } = page);
    }
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
