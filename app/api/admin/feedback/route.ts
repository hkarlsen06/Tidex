import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServiceClient } from '@/lib/supabase/service';
import { verifyAdminFromRequest } from '../_lib/verify-admin';

/**
 * GET /api/admin/feedback
 *
 * List feedback submissions with pagination support.
 *
 * Authentication:
 * - Cookie-based session (web app)
 * - Bearer token in Authorization header (native iOS app)
 * - Requires admin role (app_metadata.role === "admin")
 *
 * Query Parameters:
 * - limit: number - Items per page (default: 20)
 * - offset: number - Number of items to skip (default: 0)
 *
 * Response:
 * - 200: { feedback: FeedbackItem[], total: number }
 * - 401: { error: string } - Not authenticated or not an admin
 * - 500: { error: string } - Server error
 */

interface FeedbackItem {
  id: string;
  userId: string;
  message: string;
  userEmail: string;
  userName: string | null;
  userProfilePicture: string | null;
  createdAt: string;
  response: string | null;
  respondedAt: string | null;
  respondedBy: string | null;
}

export async function GET(request: NextRequest) {
  try {
    // Verify admin authentication
    const adminResult = await verifyAdminFromRequest(request);

    if (!adminResult) {
      return NextResponse.json(
        { error: 'Not authenticated or not an admin' },
        { status: 401 }
      );
    }

    // Use service client since we've already verified admin access
    const serviceClient = createSupabaseServiceClient();

    // Parse query parameters
    const searchParams = request.nextUrl.searchParams;
    const limit = Math.max(
      1,
      Math.min(100, parseInt(searchParams.get('limit') ?? '20', 10))
    );
    const offset = Math.max(
      0,
      parseInt(searchParams.get('offset') ?? '0', 10)
    );

    // Fetch feedback with pagination (using service client to bypass RLS)
    const { data, count, error } = await serviceClient
      .from('feedback')
      .select('*', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(offset, offset + limit - 1);

    if (error) {
      console.error('[admin/feedback] Fetch error:', error);
      return NextResponse.json(
        { error: 'Failed to fetch feedback' },
        { status: 500 }
      );
    }

    // Fetch user names and profile pictures
    const userIds = [...new Set((data ?? []).map((f) => f.user_id))];
    const userNames: Record<string, string | null> = {};
    const userProfilePictures: Record<string, string | null> = {};

    if (userIds.length > 0) {
      // Fetch users from auth
      const { data: authData } = await serviceClient.auth.admin.listUsers({
        perPage: 1000,
      });

      if (authData?.users) {
        for (const user of authData.users) {
          if (userIds.includes(user.id)) {
            userNames[user.id] =
              (user.user_metadata?.full_name as string) ?? null;
          }
        }
      }

      // Fetch profile pictures from user_settings
      const { data: settingsData } = await serviceClient
        .from('user_settings')
        .select('user_id, profile_picture_url')
        .in('user_id', userIds);

      if (settingsData) {
        for (const setting of settingsData) {
          userProfilePictures[setting.user_id] =
            setting.profile_picture_url ?? null;
        }
      }
    }

    // Transform to camelCase for Swift Codable compatibility
    const feedback: FeedbackItem[] = (data ?? []).map((item) => ({
      id: item.id,
      userId: item.user_id,
      message: item.message,
      userEmail: item.user_email,
      userName: userNames[item.user_id] ?? null,
      userProfilePicture: userProfilePictures[item.user_id] ?? null,
      createdAt: item.created_at,
      response: item.response,
      respondedAt: item.responded_at,
      respondedBy: item.responded_by,
    }));

    return NextResponse.json({
      feedback,
      total: count ?? 0,
    });
  } catch (error) {
    console.error('[admin/feedback] Exception:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
