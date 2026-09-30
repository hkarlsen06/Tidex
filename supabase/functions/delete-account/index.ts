import { withSupabase } from "@supabase/server";

const STORAGE_REMOVE_BATCH_SIZE = 100;

function jsonResponse(status: number, body: Record<string, unknown>) {
  return Response.json(body, { status });
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

const PROFILE_PICTURES_BUCKET = "profile-pictures";
const MESSAGE_ATTACHMENTS_BUCKET = "message-attachments";
const STORAGE_LIST_PAGE_SIZE = 1000;

// Profile pictures live under "<user id>/". List the folder instead of trusting
// the user-writable profile_picture_url, which could name any object.
async function listProfilePictureObjects(
  adminClient: any,
  userId: string,
): Promise<StorageObjectRow[]> {
  const objects: StorageObjectRow[] = [];

  for (let offset = 0;; offset += STORAGE_LIST_PAGE_SIZE) {
    const { data, error } = await adminClient.storage
      .from(PROFILE_PICTURES_BUCKET)
      .list(userId, { limit: STORAGE_LIST_PAGE_SIZE, offset });

    if (error) {
      throw new Error(`Failed to list profile pictures: ${error.message}`);
    }

    for (const item of data ?? []) {
      // Folders come back with a null id.
      if (item.id) {
        objects.push({
          bucket_id: PROFILE_PICTURES_BUCKET,
          path: `${userId}/${item.name}`,
        });
      }
    }

    if (!data || data.length < STORAGE_LIST_PAGE_SIZE) return objects;
  }
}

// Must run before prepare_user_for_deletion, which deletes the user's messages
// and direct threads and cascades their message_attachments rows.
async function listMessageAttachmentObjects(
  adminClient: any,
  userId: string,
): Promise<StorageObjectRow[]> {
  const { data: directThreads, error: threadsError } = await adminClient
    .from("direct_threads")
    .select("thread_id")
    .or(`user_low_id.eq.${userId},user_high_id.eq.${userId}`);

  if (threadsError) {
    throw new Error(
      `Failed to load direct threads: ${threadsError.message}`,
    );
  }

  const directThreadIds = (directThreads ?? []).map((
    row: { thread_id: string },
  ) => row.thread_id);

  const queries = [
    adminClient
      .from("message_attachments")
      .select("storage_bucket, storage_path, messages!inner(sender_user_id)")
      .eq("messages.sender_user_id", userId),
  ];
  for (const threadIds of chunk(directThreadIds, STORAGE_REMOVE_BATCH_SIZE)) {
    queries.push(
      adminClient
        .from("message_attachments")
        .select("storage_bucket, storage_path, messages!inner(thread_id)")
        .in("messages.thread_id", threadIds),
    );
  }

  const objects: StorageObjectRow[] = [];
  for (const { data, error } of await Promise.all(queries)) {
    if (error) {
      throw new Error(
        `Failed to load message attachment paths: ${error.message}`,
      );
    }
    for (const row of data ?? []) {
      if (row.storage_bucket !== MESSAGE_ATTACHMENTS_BUCKET) continue;
      objects.push({ bucket_id: row.storage_bucket, path: row.storage_path });
    }
  }

  return objects;
}

async function deleteStorageObjects(
  adminClient: any,
  ownedObjects: StorageObjectRow[],
) {
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
    { auth: "user" },
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

      // Reject before touching storage. An admin holding an impersonation
      // session must not be able to delete the target's account. The
      // per-session check (is_impersonation_session) is not executable by
      // authenticated callers, so refuse while any impersonation of this
      // user is active.
      const { data: beingImpersonated, error: impersonationError } = await ctx
        .supabaseAdmin.rpc("is_user_being_impersonated", {
          p_user_id: user.id,
        });
      if (impersonationError) {
        console.error(
          "[delete-account] impersonation check failed",
          impersonationError,
        );
        return jsonResponse(500, {
          success: false,
          error: "Failed to verify account state",
        });
      }
      if (beingImpersonated === true) {
        return jsonResponse(403, {
          success: false,
          error: "Account deletion is not allowed during impersonation",
        });
      }

      // Users with a verified MFA factor need an aal2 session, the same rule
      // as the check_mfa_aal() RLS helper.
      const { data: mfaSatisfied, error: mfaError } = await ctx.supabase.rpc(
        "check_mfa_aal",
      );
      if (mfaError) {
        console.error("[delete-account] MFA check failed", mfaError);
        return jsonResponse(500, {
          success: false,
          error: "Failed to verify account state",
        });
      }
      if (mfaSatisfied !== true) {
        return jsonResponse(403, {
          success: false,
          error: "Multi-factor authentication required",
        });
      }

      let ownedObjects: StorageObjectRow[];
      try {
        ownedObjects = [
          ...(await listProfilePictureObjects(ctx.supabaseAdmin, user.id)),
          ...(await listMessageAttachmentObjects(ctx.supabaseAdmin, user.id)),
        ];
      } catch (listError) {
        console.error("[delete-account] storage listing failed", listError);
        return jsonResponse(500, {
          success: false,
          error: "Failed to clean up account storage",
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
        await deleteStorageObjects(ctx.supabaseAdmin, ownedObjects);
      } catch (storageError) {
        console.error("[delete-account] storage cleanup failed", storageError);
        return jsonResponse(500, {
          success: false,
          error: "Failed to clean up account storage",
        });
      }

      const { error: deleteError } = await ctx.supabaseAdmin.auth.admin
        .deleteUser(user.id);
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
