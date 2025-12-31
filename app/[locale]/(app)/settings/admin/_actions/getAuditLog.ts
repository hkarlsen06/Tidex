"use server";

import { verifyAdmin } from "@/data-access/auth";
import { createSupabaseServiceClient } from "@/lib/supabase/service";
import type { AdminAction } from "@/lib/admin/action-labels";

export interface AuditLogEntry {
  id: string;
  adminId: string;
  adminEmail: string;
  action: AdminAction;
  targetUserId: string | null;
  targetEmail: string | null;
  metadata: Record<string, unknown>;
  createdAt: string;
}

interface GetAuditLogInput {
  limit?: number;
  actionFilter?: AdminAction;
  targetFilter?: string;
}

interface GetAuditLogResult {
  success: true;
  entries: AuditLogEntry[];
}

interface GetAuditLogError {
  success: false;
  message: string;
}

export async function getAuditLog(
  input: GetAuditLogInput = {}
): Promise<GetAuditLogResult | GetAuditLogError> {
  await verifyAdmin();
  const supabase = createSupabaseServiceClient();

  const limit = input.limit ?? 50;

  // Validate target filter UUID if provided
  if (
    input.targetFilter &&
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      input.targetFilter
    )
  ) {
    return { success: false, message: "Ugyldig bruker-ID format" };
  }

  const { data, error } = await supabase.rpc("admin_get_audit_log", {
    p_limit: limit,
    p_action_filter: input.actionFilter ?? null,
    p_target_filter: input.targetFilter ?? null,
  });

  if (error) {
    return {
      success: false,
      message: `Kunne ikke hente aktivitetslogg: ${error.message}`,
    };
  }

  const entries: AuditLogEntry[] = (data ?? []).map(
    (row: {
      id: string;
      admin_id: string;
      admin_email: string;
      action: AdminAction;
      target_user_id: string | null;
      target_email: string | null;
      metadata: Record<string, unknown>;
      created_at: string;
    }) => ({
      id: row.id,
      adminId: row.admin_id,
      adminEmail: row.admin_email,
      action: row.action,
      targetUserId: row.target_user_id,
      targetEmail: row.target_email,
      metadata: row.metadata ?? {},
      createdAt: row.created_at,
    })
  );

  return { success: true, entries };
}
