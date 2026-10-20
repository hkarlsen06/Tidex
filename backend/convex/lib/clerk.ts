// Clerk Backend API calls. Only actions can use these, because they call fetch.
// CLERK_SECRET_KEY is set per deployment with `convex env set`.

export type ClerkUser = {
  id: string;
  primary_email_address_id: string | null;
  email_addresses: { id: string; email_address: string }[];
  external_accounts: { provider: string; provider_user_id: string }[];
  first_name: string | null;
  last_name: string | null;
  image_url: string | null;
  has_image: boolean;
};

async function clerkGet(path: string): Promise<unknown> {
  const key = process.env.CLERK_SECRET_KEY;
  if (!key) throw new Error("CLERK_SECRET_KEY is not set");
  const response = await fetch(`https://api.clerk.com/v1${path}`, {
    headers: { Authorization: `Bearer ${key}` },
  });
  if (!response.ok) throw new Error(`Clerk GET ${path} failed with ${response.status}`);
  return await response.json();
}

export async function getClerkUser(id: string): Promise<ClerkUser> {
  return (await clerkGet(`/users/${encodeURIComponent(id)}`)) as ClerkUser;
}
