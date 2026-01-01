"use server";

import { verifyAdmin } from "@/data-access/auth";
import { createSupabaseServiceClient } from "@/lib/supabase/service";
import { logger } from "@/lib/logger";
import { revalidateTag } from "next/cache";
import type { AdminAction } from "@/lib/admin/action-labels";

export interface SqlResult {
  success: true;
  data: Record<string, unknown>[];
  rowCount: number;
  executionTimeMs: number;
}

export interface SqlError {
  success: false;
  message: string;
}

/**
 * Log an admin action to the audit log
 */
async function logAdminAction(params: {
  adminId: string;
  adminEmail: string;
  action: AdminAction;
  metadata?: Record<string, unknown>;
}) {
  const supabase = createSupabaseServiceClient();

  const { error } = await supabase.rpc("admin_log_action", {
    p_admin_id: params.adminId,
    p_admin_email: params.adminEmail,
    p_action: params.action,
    p_target_id: null,
    p_target_email: null,
    p_metadata: params.metadata ?? {},
  });

  if (error) {
    logger.error("Failed to log admin action:", error);
  }

  revalidateTag("admin-auditlog", "max");
}

export async function executeSql(
  query: string
): Promise<SqlResult | SqlError> {
  const { user } = await verifyAdmin();
  const adminEmail = user.email ?? "unknown";

  const trimmedQuery = query.trim();

  if (!trimmedQuery) {
    return { success: false, message: "Query cannot be empty" };
  }

  const supabase = createSupabaseServiceClient();
  const startTime = performance.now();

  try {
    // Use the rpc method with a raw SQL function or direct query
    // Supabase JS client doesn't have a direct SQL execution method,
    // so we need to use the REST API or create an RPC function
    // For now, let's use the postgres extension to execute raw SQL
    const { data, error } = await supabase.rpc("admin_execute_sql", {
      sql_query: trimmedQuery,
    });

    const endTime = performance.now();
    const executionTimeMs = Math.round(endTime - startTime);

    if (error) {
      logger.error("SQL execution error:", error);
      await logAdminAction({
        adminId: user.id,
        adminEmail,
        action: "admin_action_failed",
        metadata: {
          intended_action: "sql_executed",
          query: trimmedQuery,
          error: error.message,
          execution_time_ms: executionTimeMs,
        },
      });
      return {
        success: false,
        message: error.message || "Failed to execute SQL",
      };
    }

    // Handle the result - it could be an array or null
    const resultData = Array.isArray(data) ? data : data ? [data] : [];

    // Log successful execution
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "sql_executed",
      metadata: {
        query: trimmedQuery,
        row_count: resultData.length,
        execution_time_ms: executionTimeMs,
      },
    });

    return {
      success: true,
      data: resultData as Record<string, unknown>[],
      rowCount: resultData.length,
      executionTimeMs,
    };
  } catch (err) {
    logger.error("SQL execution exception:", err);
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      metadata: {
        intended_action: "sql_executed",
        query: trimmedQuery,
        error: err instanceof Error ? err.message : "Unknown error",
      },
    });
    return {
      success: false,
      message: err instanceof Error ? err.message : "Unknown error occurred",
    };
  }
}
