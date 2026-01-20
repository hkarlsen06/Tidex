import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServiceClient } from '@/lib/supabase/service';
import { verifyAdminFromRequest } from '../_lib/verify-admin';
import { logAdminAction } from '../_lib/audit-log';

/**
 * POST /api/admin/sql
 *
 * Execute a raw SQL query with admin privileges.
 * Results are logged to the audit trail for accountability.
 *
 * Authentication:
 * - Cookie-based session (web app)
 * - Bearer token in Authorization header (native iOS app)
 * - Requires admin role (app_metadata.role === "admin")
 *
 * Body:
 * - query: string - The SQL query to execute
 *
 * Response:
 * - 200: { success: true, data: Record<string, unknown>[], rowCount: number, executionTimeMs: number }
 * - 400: { success: false, message: string } - Invalid input
 * - 401: { success: false, message: string } - Not authenticated
 * - 500: { success: false, message: string } - Execution error
 */

interface SqlRequestBody {
  query: string;
}

interface SqlSuccessResponse {
  success: true;
  data: Record<string, unknown>[];
  rowCount: number;
  executionTimeMs: number;
}

interface SqlErrorResponse {
  success: false;
  message: string;
}

type SqlResponse = SqlSuccessResponse | SqlErrorResponse;

export async function POST(
  request: NextRequest
): Promise<NextResponse<SqlResponse>> {
  try {
    // Verify admin authentication
    const adminResult = await verifyAdminFromRequest(request);

    if (!adminResult) {
      return NextResponse.json(
        { success: false, message: 'Not authenticated or not an admin' },
        { status: 401 }
      );
    }

    const { user: admin } = adminResult;
    const adminEmail = admin.email ?? 'unknown';

    // Parse request body
    let body: SqlRequestBody;
    try {
      body = await request.json();
    } catch {
      return NextResponse.json(
        { success: false, message: 'Invalid JSON body' },
        { status: 400 }
      );
    }

    const { query } = body;

    // Validate query field
    if (!query || typeof query !== 'string') {
      return NextResponse.json(
        { success: false, message: 'Missing or invalid query field' },
        { status: 400 }
      );
    }

    const trimmedQuery = query.trim();

    if (!trimmedQuery) {
      return NextResponse.json(
        { success: false, message: 'Query cannot be empty' },
        { status: 400 }
      );
    }

    const supabase = createSupabaseServiceClient();
    const startTime = performance.now();

    // Execute the SQL query via RPC
    const { data, error } = await supabase.rpc('admin_execute_sql', {
      sql_query: trimmedQuery,
    });

    const endTime = performance.now();
    const executionTimeMs = Math.round(endTime - startTime);

    if (error) {
      console.error('[admin/sql] SQL execution error:', error);

      // Log failure to audit log
      await logAdminAction({
        adminId: admin.id,
        adminEmail,
        action: 'admin_action_failed',
        metadata: {
          intended_action: 'sql_executed',
          query: trimmedQuery,
          error: error.message,
          execution_time_ms: executionTimeMs,
        },
      });

      return NextResponse.json(
        { success: false, message: error.message || 'Failed to execute SQL' },
        { status: 500 }
      );
    }

    // Handle the result - it could be an array or null
    const resultData = Array.isArray(data) ? data : data ? [data] : [];

    // Log successful execution to audit log
    await logAdminAction({
      adminId: admin.id,
      adminEmail,
      action: 'sql_executed',
      metadata: {
        query: trimmedQuery,
        row_count: resultData.length,
        execution_time_ms: executionTimeMs,
      },
    });

    return NextResponse.json({
      success: true,
      data: resultData as Record<string, unknown>[],
      rowCount: resultData.length,
      executionTimeMs,
    });
  } catch (error) {
    console.error('[admin/sql] Exception:', error);
    return NextResponse.json(
      { success: false, message: 'Internal server error' },
      { status: 500 }
    );
  }
}
