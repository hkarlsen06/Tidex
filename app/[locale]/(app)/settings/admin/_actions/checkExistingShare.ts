"use server";

import { verifyAdmin } from "@/data-access/auth";
import { createSupabaseServiceClient } from "@/lib/supabase/service";

interface CheckExistingShareInput {
  ownerId: string;
  viewerId: string;
}

interface CheckExistingShareResult {
  success: true;
  exists: boolean;
  shareId?: string;
}

interface CheckExistingShareError {
  success: false;
  message: string;
}

export async function checkExistingShare(
  input: CheckExistingShareInput
): Promise<CheckExistingShareResult | CheckExistingShareError> {
  await verifyAdmin();
  const supabase = createSupabaseServiceClient();

  // Validate UUID format
  const uuidRegex =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!uuidRegex.test(input.ownerId) || !uuidRegex.test(input.viewerId)) {
    return { success: false, message: "Invalid user ID format" };
  }

  const { data, error } = await supabase
    .from("shift_shares")
    .select("id")
    .eq("owner_id", input.ownerId)
    .eq("viewer_id", input.viewerId)
    .maybeSingle();

  if (error) {
    return {
      success: false,
      message: `Could not check for existing share: ${error.message}`,
    };
  }

  return {
    success: true,
    exists: !!data,
    shareId: data?.id,
  };
}
