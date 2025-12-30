"use server";

import { verifyAdmin } from "@/data-access/auth";
import { createSupabaseServiceClient } from "@/lib/supabase/service";

type TargetAudience = "all" | "pro" | "active";

export async function previewTargetCount(
  target: TargetAudience,
  includeSelf: boolean
) {
  const { user } = await verifyAdmin();

  // Service role to call admin RPC (efficient COUNT functions)
  const supabase = createSupabaseServiceClient();

  let rpcName: string;
  let rpcParams: Record<string, unknown> = {};

  switch (target) {
    case "pro":
      rpcName = "admin_count_target_users_pro";
      break;
    case "active":
      rpcName = "admin_count_target_users_active";
      break;
    default:
      rpcName = "admin_count_target_users_all";
      rpcParams = { exclude_user_id: includeSelf ? null : user.id };
  }

  const { data, error } = await supabase.rpc(rpcName, rpcParams);
  if (error) return { count: 0, error: error.message };

  // COUNT functions return BIGINT directly
  return { count: Number(data) || 0 };
}
