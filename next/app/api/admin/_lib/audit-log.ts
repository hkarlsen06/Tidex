import { createSupabaseServiceClient } from '@/lib/supabase/service';
import type { AdminAction } from '@/lib/admin/action-labels';

interface LogAdminActionParams {
  adminId: string;
  adminEmail: string;
  action: AdminAction;
  targetId?: string;
  targetEmail?: string;
  metadata?: Record<string, unknown>;
}

/**
 * Log an admin action to the audit log
 * Uses service role to bypass RLS
 */
export async function logAdminAction(params: LogAdminActionParams): Promise<void> {
  const supabase = createSupabaseServiceClient();

  const { error } = await supabase.rpc('admin_log_action', {
    p_admin_id: params.adminId,
    p_admin_email: params.adminEmail,
    p_action: params.action,
    p_target_id: params.targetId ?? null,
    p_target_email: params.targetEmail ?? null,
    p_metadata: params.metadata ?? {},
  });

  if (error) {
    console.error('[admin-audit] Failed to log admin action:', error);
  }
}
