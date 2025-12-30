"use server";

import { verifyAdmin } from "@/data-access/auth";
import { createSupabaseServiceClient } from "@/lib/supabase/service";

export interface BroadcastRecord {
  id: string;
  title: string;
  body: string;
  target: string;
  target_count: number;
  status: string;
  created_at: string;
  sent_count: number;
  failed_count: number;
  skipped_count: number;
  pending_count: number;
}

export async function getBroadcastHistory(): Promise<BroadcastRecord[]> {
  await verifyAdmin();

  // Service role to call admin RPC
  const supabase = createSupabaseServiceClient();

  const { data, error } = await supabase.rpc("admin_get_broadcast_history", {
    limit_count: 10,
  });

  if (error) {
    console.error("Failed to fetch history:", error);
    return [];
  }

  return data || [];
}
