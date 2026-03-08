"use server";

import { verifyAdmin } from "@/data-access/auth";
import { createSupabaseServiceClient } from "@/lib/supabase/service";

export interface ShiftShareItem {
  id: string;
  ownerId: string;
  ownerEmail: string | null;
  ownerName: string | null;
  ownerPhone: string | null;
  viewerId: string;
  viewerEmail: string | null;
  viewerName: string | null;
  viewerPhone: string | null;
  createdAt: string;
  showEarnings: boolean;
  blocked: boolean;
  muted: boolean;
}

interface GetShiftSharesInput {
  search?: string;
  page?: number;
  pageSize?: number;
  sortBy?: "created_at" | "owner_name" | "viewer_name";
  sortOrder?: "asc" | "desc";
}

interface GetShiftSharesResult {
  success: true;
  shares: ShiftShareItem[];
  totalCount: number;
  page: number;
  pageSize: number;
}

interface GetShiftSharesError {
  success: false;
  message: string;
}

export async function getShiftShares(
  input: GetShiftSharesInput = {}
): Promise<GetShiftSharesResult | GetShiftSharesError> {
  await verifyAdmin();
  const supabase = createSupabaseServiceClient();

  const page = input.page ?? 1;
  const pageSize = input.pageSize ?? 20;
  const sortBy = input.sortBy ?? "created_at";
  const sortOrder = input.sortOrder ?? "desc";
  const search = input.search?.trim().toLowerCase() ?? "";

  // Build the SQL order clause
  let orderClause: string;
  switch (sortBy) {
    case "owner_name":
      orderClause = `COALESCE(o.raw_user_meta_data->>'full_name', o.email, o.phone, ss.owner_id::text) ${sortOrder}`;
      break;
    case "viewer_name":
      orderClause = `COALESCE(v.raw_user_meta_data->>'full_name', v.email, v.phone, ss.viewer_id::text) ${sortOrder}`;
      break;
    default:
      orderClause = `ss.created_at ${sortOrder}`;
  }

  // Build search filter
  let searchFilter = "";
  if (search) {
    // Escape single quotes for SQL safety
    const escapedSearch = search.replace(/'/g, "''");
    searchFilter = `
      AND (
        LOWER(o.email) LIKE '%${escapedSearch}%'
        OR LOWER(o.phone) LIKE '%${escapedSearch}%'
        OR LOWER(o.raw_user_meta_data->>'full_name') LIKE '%${escapedSearch}%'
        OR LOWER(ss.owner_id::text) LIKE '%${escapedSearch}%'
        OR LOWER(v.email) LIKE '%${escapedSearch}%'
        OR LOWER(v.phone) LIKE '%${escapedSearch}%'
        OR LOWER(v.raw_user_meta_data->>'full_name') LIKE '%${escapedSearch}%'
        OR LOWER(ss.viewer_id::text) LIKE '%${escapedSearch}%'
      )
    `;
  }

  // Get total count
  const countQuery = `
    SELECT COUNT(*) as count
    FROM shift_shares ss
    LEFT JOIN auth.users o ON ss.owner_id = o.id
    LEFT JOIN auth.users v ON ss.viewer_id = v.id
    WHERE 1=1 ${searchFilter}
  `;

  const { data: countData, error: countError } = await supabase.rpc(
    "admin_execute_sql",
    { sql_query: countQuery }
  );

  if (countError) {
    return {
      success: false,
      message: `Kunne ikke hente antall delinger: ${countError.message}`,
    };
  }

  const totalCount = countData?.[0]?.count ?? 0;

  // Get paginated results
  const offset = (page - 1) * pageSize;
  const dataQuery = `
    SELECT
      ss.id,
      ss.owner_id,
      o.email as owner_email,
      o.raw_user_meta_data->>'full_name' as owner_name,
      o.phone as owner_phone,
      ss.viewer_id,
      v.email as viewer_email,
      v.raw_user_meta_data->>'full_name' as viewer_name,
      v.phone as viewer_phone,
      ss.created_at,
      ss.show_earnings,
      ss.hidden as blocked,
      ss.muted
    FROM shift_shares ss
    LEFT JOIN auth.users o ON ss.owner_id = o.id
    LEFT JOIN auth.users v ON ss.viewer_id = v.id
    WHERE 1=1 ${searchFilter}
    ORDER BY ${orderClause}
    LIMIT ${pageSize}
    OFFSET ${offset}
  `;

  const { data, error } = await supabase.rpc("admin_execute_sql", {
    sql_query: dataQuery,
  });

  if (error) {
    return {
      success: false,
      message: `Kunne ikke hente delinger: ${error.message}`,
    };
  }

  const shares: ShiftShareItem[] = (data ?? []).map(
    (row: {
      id: string;
      owner_id: string;
      owner_email: string | null;
      owner_name: string | null;
      owner_phone: string | null;
      viewer_id: string;
      viewer_email: string | null;
      viewer_name: string | null;
      viewer_phone: string | null;
      created_at: string;
      show_earnings: boolean;
      blocked: boolean;
      muted: boolean;
    }) => ({
      id: row.id,
      ownerId: row.owner_id,
      ownerEmail: row.owner_email,
      ownerName: row.owner_name,
      ownerPhone: row.owner_phone,
      viewerId: row.viewer_id,
      viewerEmail: row.viewer_email,
      viewerName: row.viewer_name,
      viewerPhone: row.viewer_phone,
      createdAt: row.created_at,
      showEarnings: row.show_earnings,
      blocked: row.blocked,
      muted: row.muted,
    })
  );

  return {
    success: true,
    shares,
    totalCount,
    page,
    pageSize,
  };
}
