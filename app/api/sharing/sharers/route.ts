import { NextResponse } from "next/server";
import { getSession } from "@/data-access/auth";
import { getUsersWhoSharedWithMe } from "@/data-access/sharing";
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
  // Manual auth check for API routes (redirect() not supported)
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const sharers = await getUsersWhoSharedWithMe(session.user.id);

    // Map to the format expected by iOS, adding the blocked field
    // (getUsersWhoSharedWithMe excludes blocked sharers, so blocked is always false here)
    const response = sharers.map((sharer) => ({
      id: sharer.id,
      email: sharer.email,
      phone: sharer.phone,
      firstName: sharer.firstName,
      profilePictureUrl: sharer.profilePictureUrl,
      oauthAvatarUrl: sharer.oauthAvatarUrl,
      sharedAt: sharer.sharedAt,
      showEarnings: sharer.showEarnings,
      blocked: false, // getUsersWhoSharedWithMe filters out blocked
    }));

    return NextResponse.json(
      { sharers: response },
      {
        headers: {
          // Cache for 5 minutes with stale-while-revalidate
          // 'private' prevents CDN caching; browser caching is safe since
          // the JWT in Authorization header scopes the request to the user
          "Cache-Control": "private, max-age=300, stale-while-revalidate=60",
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
