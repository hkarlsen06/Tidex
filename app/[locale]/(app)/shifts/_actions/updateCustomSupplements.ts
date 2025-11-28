"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";
import { verifySession } from "@/data-access/auth";
import { ERRORS } from "@/lib/errors/messages";
import type { CustomSupplementsData } from "@/lib/payroll/types";
import { validateCustomSupplements } from "@/lib/payroll/effect";
import { Effect } from "effect";

export type UpdateCustomSupplementsInput = {
  shiftId: string;
  customSupplements: CustomSupplementsData | null;
  recurringId?: string; // If present, update recurring shift date_specific_supplements
  shiftDate?: string; // Required if recurringId is present
};

/**
 * Update custom supplements for a shift
 * - For regular shifts: updates user_shifts.custom_supplements
 * - For ghost shifts: updates recurring shift date_specific_supplements
 */
export async function updateCustomSupplements(input: UpdateCustomSupplementsInput) {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  if (!input.shiftId) {
    throw new Error(ERRORS.INVALID_SHIFT_ID);
  }

  // Validate custom supplements if provided
  if (input.customSupplements) {
    const validation = await Effect.runPromise(
      Effect.either(validateCustomSupplements(input.customSupplements))
    );
    if (validation._tag === "Left") {
      throw new Error("Invalid custom supplements data");
    }
  }

  // Handle recurring shift ghost
  if (input.recurringId && input.shiftDate) {
    // Verify recurring shift ownership
    const { data: recurring, error: recurringError } = await supabase
      .from("recurring_shifts")
      .select("id, date_specific_supplements")
      .eq("id", input.recurringId)
      .eq("user_id", user.id)
      .single();

    if (recurringError || !recurring) {
      throw new Error(ERRORS.SHIFT_NOT_FOUND);
    }

    // Update or remove date-specific supplements
    const updatedDateSupplements = { ...(recurring.date_specific_supplements || {}) };

    if (input.customSupplements) {
      updatedDateSupplements[input.shiftDate] = input.customSupplements;
    } else {
      delete updatedDateSupplements[input.shiftDate];
    }

    const { error } = await supabase
      .from("recurring_shifts")
      .update({
        date_specific_supplements: Object.keys(updatedDateSupplements).length > 0
          ? updatedDateSupplements
          : null,
      })
      .eq("id", input.recurringId)
      .eq("user_id", user.id);

    if (error) {
      throw new Error(error.message);
    }
  } else {
    // Handle regular shift
    const { data: existing, error: fetchError } = await supabase
      .from("user_shifts")
      .select("id")
      .eq("id", input.shiftId)
      .eq("user_id", user.id)
      .single();

    if (fetchError || !existing) {
      throw new Error(ERRORS.SHIFT_NOT_FOUND);
    }

    const { error } = await supabase
      .from("user_shifts")
      .update({
        custom_supplements: input.customSupplements,
      })
      .eq("id", input.shiftId)
      .eq("user_id", user.id);

    if (error) {
      throw new Error(error.message);
    }
  }

  // Invalidate cache and revalidate paths
  invalidateAndRevalidate(user.id);

  return { updated: 1 };
}
