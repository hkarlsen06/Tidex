export type ClerkImportUser = {
  id: string;
  email: string | null;
  proven_emails: string[] | null;
  apple_subject: string | null;
  password_hash: string | null;
  created_at: string;
};

type ClerkEmail = {
  id: string;
  email_address: string;
  verification: { status: string } | null;
  linked_to: { type: string; id: string }[];
};

export type ClerkUser = {
  id: string;
  external_id: string | null;
  primary_email_address_id: string | null;
  email_addresses: ClerkEmail[];
};

type ClerkRequest = (method: string, path: string, body?: object) => Promise<unknown>;

const isObject = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === "object" && !Array.isArray(value);

function object(value: unknown): Record<string, unknown> {
  if (!isObject(value)) throw new Error("Invalid Clerk object");
  return value;
}

function string(value: unknown): string {
  if (typeof value !== "string") throw new Error("Invalid Clerk string");
  return value;
}

function nullableString(value: unknown): string | null {
  return value === null ? null : string(value);
}

function email(value: unknown): ClerkEmail {
  const row = object(value);
  if (!Array.isArray(row.linked_to)) throw new Error("Invalid Clerk email links");
  return {
    id: string(row.id),
    email_address: string(row.email_address),
    verification: row.verification === null ? null : { status: string(object(row.verification).status) },
    linked_to: row.linked_to.map((value: unknown) => {
      const link = object(value);
      return { id: string(link.id), type: string(link.type) };
    }),
  };
}

export function parseClerkUsers(value: unknown): ClerkUser[] {
  if (!Array.isArray(value)) throw new Error("Invalid Clerk users");
  return value.map((value: unknown) => {
    const row = object(value);
    if (!Array.isArray(row.email_addresses)) throw new Error("Invalid Clerk emails");
    return {
      id: string(row.id),
      external_id: nullableString(row.external_id),
      primary_email_address_id: nullableString(row.primary_email_address_id),
      email_addresses: row.email_addresses.map(email),
    };
  });
}

/** Imports verified addresses, or an Apple account whose provider identity survived without email. */
export async function syncClerkUser(u: ClerkImportUser, clerk: ClerkRequest, log: (message: string) => void): Promise<string | null> {
  const emails = u.proven_emails ?? [];
  const existing = parseClerkUsers(await clerk("GET", `/users?external_id=${encodeURIComponent(u.id)}`));
  if (emails.length === 0) {
    if (!u.apple_subject?.trim()) {
      if (existing.length > 0) log(`Clerk user ${existing[0]!.id} of ${u.id} has no proven email left. Left as it is.`);
      return null;
    }
    if (existing.length > 0) return existing[0]!.id;
    // Clerk requires an identifier even for a migration. This username supplies no
    // password or email access. The existing GoTrue session proves ownership at exchange.
    const created = object(await clerk("POST", "/users", {
      external_id: u.id,
      username: `legacy_${u.id.replaceAll("-", "")}`,
      skip_user_requirement: true,
      skip_password_requirement: true,
      created_at: u.created_at,
    }));
    return string(created.id);
  }
  const ordered = [...new Set([u.email, ...emails].filter((e): e is string => e !== null && emails.includes(e)))];
  const password = u.password_hash?.startsWith("$2") ? { password_digest: u.password_hash, password_hasher: "bcrypt" } : {};
  if (existing.length === 0) {
    const created = object(await clerk("POST", "/users", {
      external_id: u.id,
      email_address: ordered,
      ...password,
      skip_password_checks: true,
      skip_password_requirement: true,
      created_at: u.created_at,
    }));
    return string(created.id);
  }
  const user = existing[0]!;
  const have = new Map(user.email_addresses.map((e) => [e.email_address.toLowerCase(), e]));
  for (const address of ordered) {
    const e = have.get(address);
    if (e === undefined) {
      have.set(address, email(await clerk("POST", "/email_addresses", { user_id: user.id, email_address: address, verified: true })));
    } else if (e.verification?.status !== "verified") {
      await clerk("PATCH", `/email_addresses/${e.id}`, { verified: true });
    }
  }
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
