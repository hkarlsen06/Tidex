"use server";

import { verifyAdmin } from "@/data-access/auth";
import { createSupabaseServiceClient } from "@/lib/supabase/service";

/**
 * Extended user type that includes phone field from Supabase Auth
 */
type AdminUser = {
  id: string;
  email?: string;
  phone?: string;
  user_metadata?: Record<string, unknown>;
};

export interface UserWithPushToken {
  id: string;
  email: string | null;
  phone: string | null;
  name: string | null;
}

interface GetUsersWithPushTokensResult {
  success: true;
  users: UserWithPushToken[];
}

interface GetUsersWithPushTokensError {
  success: false;
  message: string;
}

/**
 * Get users who have registered push notification tokens.
 * Only these users can receive push notifications.
 */
export async function getUsersWithPushTokens(): Promise<
  GetUsersWithPushTokensResult | GetUsersWithPushTokensError
> {
  await verifyAdmin();
  const supabase = createSupabaseServiceClient();

  // Get distinct user_ids from push_devices table
  const { data: pushDevices, error: pushError } = await supabase
    .schema("internal").from("push_devices")
    .select("user_id")
    .order("last_seen_at", { ascending: false });

  if (pushError) {
    return {
      success: false,
      message: `Kunne ikke hente push-enheter: ${pushError.message}`,
    };
  }

  if (!pushDevices || pushDevices.length === 0) {
    return { success: true, users: [] };
  }

  // Get unique user IDs
  const userIds = [...new Set(pushDevices.map((d) => d.user_id))];

  // Fetch user info from auth admin API
  const userMap = new Map<
    string,
    { email: string | null; phone: string | null; name: string | null }
  >();

  // Fetch all users and filter by IDs
  const { data: authData, error: authError } =
    await supabase.auth.admin.listUsers({
      page: 1,
      perPage: 1000,
    });

  if (authError) {
    return {
      success: false,
      message: `Kunne ikke hente brukerinfo: ${authError.message}`,
    };
  }

  // Cast to AdminUser[] to access phone field
  const adminUsers = authData.users as unknown as AdminUser[];

  for (const user of adminUsers) {
    if (userIds.includes(user.id)) {
      userMap.set(user.id, {
        email: user.email || null,
        phone: user.phone || (user.user_metadata?.phone as string | undefined) || null,
        name: (user.user_metadata?.full_name as string) || null,
      });
    }
  }

  // Build result list maintaining order by last_seen_at
  const users: UserWithPushToken[] = [];
  const seenIds = new Set<string>();

  for (const device of pushDevices) {
    if (seenIds.has(device.user_id)) continue;
    seenIds.add(device.user_id);

    const userInfo = userMap.get(device.user_id);
    if (userInfo) {
      users.push({
        id: device.user_id,
        email: userInfo.email,
        phone: userInfo.phone,
        name: userInfo.name,
      });
    }
  }

  return { success: true, users };
}
