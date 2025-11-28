import { NextRequest, NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";

/**
 * API route for fetching a single recurring shift by ID
 */
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const { id } = await params;

  if (!id) {
    return NextResponse.json({ error: 'Missing recurring shift ID' }, { status: 400 });
  }

  try {
    const { data: recurring, error } = await supabase
      .from("recurring_shifts")
      .select("*")
      .eq("id", id)
      .eq("user_id", user.id)
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
