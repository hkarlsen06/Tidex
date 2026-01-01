"use server";

import { verifyAdmin } from "@/data-access/auth";
import { createSupabaseServiceClient } from "@/lib/supabase/service";

export interface UserSelectOption {
  id: string;
  label: string;
  email: string | null;
  name: string | null;
  phone: string | null;
}

interface SearchUsersInput {
  query: string;
  excludeUserId?: string;
  limit?: number;
}

interface SearchUsersResult {
  success: true;
  users: UserSelectOption[];
}

interface SearchUsersError {
  success: false;
  message: string;
}

export async function searchUsersForSelect(
  input: SearchUsersInput
): Promise<SearchUsersResult | SearchUsersError> {
  await verifyAdmin();
  const supabase = createSupabaseServiceClient();

  const query = input.query?.trim().toLowerCase() ?? "";
  const limit = Math.min(input.limit ?? 20, 50);

  // Require at least 2 characters for search
  if (query.length < 2) {
    return { success: true, users: [] };
  }

  // Escape single quotes for SQL safety
  const escapedQuery = query.replace(/'/g, "''");

  // Build exclude filter
  let excludeFilter = "";
  if (input.excludeUserId) {
    // Validate UUID format
    if (
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        input.excludeUserId
      )
    ) {
      return { success: false, message: "Invalid exclude user ID format" };
    }
    excludeFilter = `AND u.id != '${input.excludeUserId}'`;
  }

  const searchQuery = `
    SELECT
      u.id,
      u.email,
      u.phone,
      u.raw_user_meta_data->>'full_name' as name
    FROM auth.users u
    WHERE (
      LOWER(u.email) LIKE '%${escapedQuery}%'
      OR LOWER(u.phone) LIKE '%${escapedQuery}%'
      OR LOWER(u.raw_user_meta_data->>'full_name') LIKE '%${escapedQuery}%'
      OR LOWER(u.id::text) LIKE '%${escapedQuery}%'
    )
    ${excludeFilter}
    ORDER BY
      CASE
        WHEN LOWER(u.raw_user_meta_data->>'full_name') LIKE '${escapedQuery}%' THEN 1
        WHEN LOWER(u.email) LIKE '${escapedQuery}%' THEN 2
        WHEN LOWER(u.phone) LIKE '${escapedQuery}%' THEN 3
        ELSE 4
      END,
      COALESCE(u.raw_user_meta_data->>'full_name', u.email, u.phone, u.id::text)
    LIMIT ${limit}
  `;

  const { data, error } = await supabase.rpc("admin_execute_sql", {
    sql_query: searchQuery,
  });

  if (error) {
    return {
      success: false,
      message: `Kunne ikke søke etter brukere: ${error.message}`,
    };
  }

  const users: UserSelectOption[] = (data ?? []).map(
    (row: {
      id: string;
      email: string | null;
      phone: string | null;
      name: string | null;
    }) => {
      // Build a descriptive label
      let label: string;
      if (row.name && row.email) {
        label = `${row.name} (${row.email})`;
      } else if (row.name && row.phone) {
        label = `${row.name} (${row.phone})`;
      } else if (row.email) {
        label = row.email;
      } else if (row.phone) {
        label = row.phone;
      } else {
        label = row.id.slice(0, 8);
      }

      return {
        id: row.id,
        label,
        email: row.email,
        name: row.name,
        phone: row.phone,
      };
    }
  );

  return { success: true, users };
}
