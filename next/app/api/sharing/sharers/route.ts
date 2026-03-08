import { NextResponse } from "next/server";
import { getSession } from "@/data-access/auth";
import { getUsersWhoSharedWithMeWithUserId } from "@/data-access/sharing";
import { isTaggedError } from "@/lib/errors/tagged";

/**
 * API route for fetching users who have shared their shifts with the current user
 *
 * GET: Fetch list of sharers with full profile data
 *
 * This endpoint exists because iOS cannot use the Supabase admin client
 * to access user profile data from auth.users. The web server uses the
 * service role key to fetch email, phone, firstName, and oauthAvatarUrl.
 *
 * Authentication:
 * - iOS: Bearer token in Authorization header (handled by getSession)
 * - Web: Cookie-based session (handled by getSession)
 *
 * Response format:
 * {
 *   sharers: Array<{
 *     id: string;
 *     email: string | null;
 *     phone: string | null;
 *     firstName: string | null;
 *     profilePictureUrl: string | null;
 *     oauthAvatarUrl: string | null;
 *     sharedAt: string;
 *     showEarnings: boolean;
 *     blocked: boolean;
 *   }>
 * }
 */
export async function GET() {
  // getSession now handles both Bearer tokens (iOS) and cookies (web)
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const sharers = await getUsersWhoSharedWithMeWithUserId(session.user.id);

    // Map to the format expected by iOS, adding the legacy blocked field.
    // getUsersWhoSharedWithMe filters out hidden sharers, so this stays false.
    const response = sharers.map((sharer) => ({
      id: sharer.id,
      email: sharer.email,
      phone: sharer.phone,
      firstName: sharer.firstName,
      profilePictureUrl: sharer.profilePictureUrl,
      oauthAvatarUrl: sharer.oauthAvatarUrl,
      sharedAt: sharer.sharedAt,
      showEarnings: sharer.showEarnings,
      blocked: false, // getUsersWhoSharedWithMe filters out hidden sharers
    }));

    return NextResponse.json(
      { sharers: response },
      {
        headers: {
          // No caching - data can change frequently during management
          "Cache-Control": "private, no-cache, no-store, must-revalidate",
        },
      }
    );
  } catch (error) {
    console.error("Failed to fetch sharers:", error);

    // Check for specific tagged error types
    if (isTaggedError(error)) {
      switch (error._tag) {
        case "AuthError":
          return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
        case "NotFoundError":
          return NextResponse.json({ error: "Not found" }, { status: 404 });
        case "ValidationError":
          return NextResponse.json({ error: "Invalid request" }, { status: 400 });
        // DatabaseError, SupabaseError, etc. fall through to 500
      }
    }

    return NextResponse.json(
      { error: "Failed to fetch sharers" },
      { status: 500 }
    );
  }
}
