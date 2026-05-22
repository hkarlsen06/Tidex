import { withSupabase } from "npm:@supabase/server@1.0.0";
import { corsHeaders } from "../_shared/cors.ts";

const STORAGE_REMOVE_BATCH_SIZE = 100;

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
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

function parsePublicStorageURL(
  value: string | null | undefined,
): StorageObjectRow | null {
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
    throw new Error(
      `Failed to load profile picture path: ${settingsError.message}`,
    );
  }

  const profilePictureObject = parsePublicStorageURL(
    settings?.profile_picture_url,
  );
  if (profilePictureObject) {
    objects.push(profilePictureObject);
  }

  const { data: attachments, error: attachmentsError } = await adminClient
    .from("message_attachments")
    .select("storage_bucket, storage_path, messages!inner(sender_user_id)")
    .eq("messages.sender_user_id", userId);

  if (attachmentsError) {
    throw new Error(
      `Failed to load message attachment paths: ${attachmentsError.message}`,
    );
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

export default {
  fetch: withSupabase<any>(
    { auth: "user", cors: corsHeaders },
    async (request, ctx) => {
      if (request.method !== "DELETE" && request.method !== "POST") {
        return jsonResponse(405, {
          success: false,
          error: "Method not allowed",
        });
      }

      const {
        data: { user },
        error: userError,
      } = await ctx.supabase.auth.getUser();

      if (userError || !user) {
        return jsonResponse(401, {
          success: false,
          error: "Not authenticated",
        });
      }

      const { error: cleanupError } = await ctx.supabase.rpc(
        "prepare_user_for_deletion",
        {
          target_user_id: user.id,
        },
      );

      if (cleanupError) {
        console.error(
          "[delete-account] prepare_user_for_deletion failed",
          cleanupError,
        );
        return jsonResponse(500, {
          success: false,
          error: "Failed to prepare account deletion",
        });
      }

      try {
        await deleteOwnedStorageObjects(ctx.supabaseAdmin, user.id);
      } catch (storageError) {
        console.error("[delete-account] storage cleanup failed", storageError);
        return jsonResponse(500, {
          success: false,
          error: "Failed to clean up account storage",
        });
      }

      const { error: deleteError } =
        await ctx.supabaseAdmin.auth.admin.deleteUser(user.id);
      if (deleteError) {
        console.error("[delete-account] deleteUser failed", deleteError);
        return jsonResponse(500, {
          success: false,
          error: "Failed to delete account",
        });
      }

      return jsonResponse(200, { success: true });
    },
  ),
};
