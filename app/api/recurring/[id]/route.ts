import { NextRequest, NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";

/**
 * API route for fetching a single recurring shift by ID
 *
 * Uses getClaims() for performance - parses JWT locally without network request.
 * See: https://supabase.com/docs/reference/javascript/auth-getclaims
 */
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const supabase = await createSupabaseServerClient();

  // Use getClaims() for performance - parses JWT locally without network request
  const { data, error: authError } = await supabase.auth.getClaims();

  if (authError || !data?.claims) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const userId = data.claims.sub;
  const { id } = await params;

  if (!id) {
    return NextResponse.json({ error: 'Missing recurring shift ID' }, { status: 400 });
  }

  try {
    const { data: recurring, error } = await supabase
      .from("recurring_shifts")
      .select("*")
      .eq("id", id)
      .eq("user_id", userId)
      .single();

    if (error || !recurring) {
      console.error('Failed to load recurring shift:', error);
      return NextResponse.json(
        { error: 'Recurring shift not found' },
        { status: 404 }
      );
    }

    return NextResponse.json(recurring);
  } catch (error) {
    console.error('Failed to fetch recurring shift:', error);
    return NextResponse.json(
      { error: 'Failed to fetch recurring shift' },
      { status: 500 }
    );
  }
}
