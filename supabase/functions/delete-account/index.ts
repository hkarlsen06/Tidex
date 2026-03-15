import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { corsHeaders } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const STORAGE_REMOVE_BATCH_SIZE = 100;

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function getAuthHeader(request: Request) {
  return request.headers.get("Authorization") ?? "";
}

type StorageObjectRow = {
  bucket_id: string;
  path: string;
};

function chunk<T>(items: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let index = 0; index < items.length; index += size) {
    chunks.push(items.slice(index, index + size));
  }
  return chunks;
}

function parsePublicStorageURL(value: string | null | undefined): StorageObjectRow | null {
  if (!value) return null;

  try {
    const url = new URL(value);
    const marker = "/storage/v1/object/public/";
    const index = url.pathname.indexOf(marker);
    if (index === -1) return null;

    const suffix = url.pathname.slice(index + marker.length);
    const [bucket, ...pathParts] = suffix.split("/").filter(Boolean);
    if (!bucket || pathParts.length === 0) return null;

    return {
      bucket_id: bucket,
      path: pathParts.join("/"),
    };
  } catch {
    return null;
  }
}

async function listOwnedStorageObjects(
  adminClient: any,
  userId: string,
): Promise<StorageObjectRow[]> {
  const objects: StorageObjectRow[] = [];

  const { data: settings, error: settingsError } = await adminClient
    .from("user_settings")
    .select("profile_picture_url")
    .eq("user_id", userId)
    .maybeSingle();

  if (settingsError) {
    throw new Error(`Failed to load profile picture path: ${settingsError.message}`);
  }

  const profilePictureObject = parsePublicStorageURL(settings?.profile_picture_url);
  if (profilePictureObject) {
    objects.push(profilePictureObject);
  }

  const { data: attachments, error: attachmentsError } = await adminClient
    .from("message_attachments")
    .select("storage_bucket, storage_path, messages!inner(sender_user_id)")
    .eq("messages.sender_user_id", userId);

  if (attachmentsError) {
    throw new Error(`Failed to load message attachment paths: ${attachmentsError.message}`);
  }

  for (const attachment of attachments ?? []) {
    const row = attachment as { storage_bucket: string; storage_path: string };
    objects.push({
      bucket_id: row.storage_bucket,
      path: row.storage_path,
    });
  }

  return objects;
}

async function deleteOwnedStorageObjects(adminClient: any, userId: string) {
  const ownedObjects = await listOwnedStorageObjects(adminClient, userId);
  const pathsByBucket = new Map<string, string[]>();
  const seen = new Set<string>();

  for (const object of ownedObjects) {
    const dedupeKey = `${object.bucket_id}:${object.path}`;
    if (seen.has(dedupeKey)) continue;
    seen.add(dedupeKey);

    const paths = pathsByBucket.get(object.bucket_id) ?? [];
    paths.push(object.path);
    pathsByBucket.set(object.bucket_id, paths);
  }

  for (const [bucket, paths] of pathsByBucket.entries()) {
    for (const batch of chunk(paths, STORAGE_REMOVE_BATCH_SIZE)) {
      const { error: removeError } = await adminClient.storage
        .from(bucket)
        .remove(batch);

      if (removeError) {
        throw new Error(
          `Failed to delete storage objects from ${bucket}: ${removeError.message}`,
        );
      }
    }
  }
}

serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "DELETE" && request.method !== "POST") {
    return jsonResponse(405, { success: false, error: "Method not allowed" });
  }

  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
    return jsonResponse(500, { success: false, error: "Missing Supabase configuration" });
  }

  const authHeader = getAuthHeader(request);
  if (!authHeader.startsWith("Bearer ")) {
    return jsonResponse(401, { success: false, error: "Missing bearer token" });
  }

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false },
    global: { headers: { Authorization: authHeader } },
  });

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser();

  if (userError || !user) {
    return jsonResponse(401, { success: false, error: "Not authenticated" });
  }

  const { error: cleanupError } = await userClient.rpc("prepare_user_for_deletion", {
    target_user_id: user.id,
  });

  if (cleanupError) {
    console.error("[delete-account] prepare_user_for_deletion failed", cleanupError);
    return jsonResponse(500, { success: false, error: "Failed to prepare account deletion" });
  }

  try {
    await deleteOwnedStorageObjects(adminClient, user.id);
  } catch (storageError) {
    console.error("[delete-account] storage cleanup failed", storageError);
    return jsonResponse(500, { success: false, error: "Failed to clean up account storage" });
  }

  const { error: deleteError } = await adminClient.auth.admin.deleteUser(user.id);
  if (deleteError) {
    console.error("[delete-account] deleteUser failed", deleteError);
    return jsonResponse(500, { success: false, error: "Failed to delete account" });
  }

  return jsonResponse(200, { success: true });
});
