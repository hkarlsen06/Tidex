import { buildICalendarFeed } from "./ics.ts";
import { createFeedWindow } from "./date.ts";
import { loadCalendarData, projectRecurringShifts } from "./data.ts";
import type {
  CalendarSubscriptionContentMode,
  CalendarSupabaseClient,
} from "./types.ts";

const REQUEST_ID_HEADER = "x-calendar-feed-request-id";
const CALENDAR_CONTENT_TYPE = "text/calendar; charset=utf-8";
const TOKEN_PATTERN = /^tidex_cal_[0-9a-f]{64}$/;

type ResolverRow = {
  user_id: string;
  content_mode: CalendarSubscriptionContentMode;
};

export type CalendarFeedHandlerOptions = {
  supabase: CalendarSupabaseClient;
  now?: () => Date;
};

function calendarHeaders(requestId: string): HeadersInit {
  return {
    "Content-Type": CALENDAR_CONTENT_TYPE,
    "Cache-Control": "private, no-store",
    [REQUEST_ID_HEADER]: requestId,
  };
}

function empty(status: number, requestId: string): Response {
  return new Response(null, {
    status,
    headers: {
      "Cache-Control": "private, no-store",
      [REQUEST_ID_HEADER]: requestId,
    },
  });
}

export function extractRawToken(req: Request): string | null {
  const url = new URL(req.url);
  const segment = url.pathname.split("/").filter(Boolean).at(-1);
  if (!segment) return null;

  const token = segment.endsWith(".ics") ? segment.slice(0, -4) : segment;
  return TOKEN_PATTERN.test(token) ? token : null;
}

async function resolveSubscription(
  supabase: CalendarSupabaseClient,
  rawToken: string,
): Promise<ResolverRow | null> {
  const query = supabase.rpc("resolve_calendar_subscription_token", {
    p_raw_token: rawToken,
  });

  // deno-lint-ignore no-explicit-any
  const result = typeof (query as any).maybeSingle === "function"
    // deno-lint-ignore no-explicit-any
    ? await (query as any).maybeSingle()
    : await query as {
      data: ResolverRow | ResolverRow[] | null;
      error: { message?: string } | null;
    };

  if (result.error) {
    throw new Error(
      result.error.message ?? "Calendar subscription resolver failed",
    );
  }

  if (Array.isArray(result.data)) {
    return result.data[0] ?? null;
  }

  return result.data ?? null;
}

export function createCalendarFeedHandler(
  options: CalendarFeedHandlerOptions,
): (req: Request) => Promise<Response> {
  return async (req: Request): Promise<Response> => {
    const requestId = crypto.randomUUID();

    if (req.method !== "GET" && req.method !== "HEAD") {
      return empty(405, requestId);
    }

    const rawToken = extractRawToken(req);
    if (!rawToken) {
      return empty(404, requestId);
    }

    try {
      const subscription = await resolveSubscription(
        options.supabase,
        rawToken,
      );
      if (!subscription) {
        return empty(404, requestId);
      }

      const window = createFeedWindow(options.now?.() ?? new Date());
      const data = await loadCalendarData(
        options.supabase,
        subscription.user_id,
        subscription.content_mode,
        window,
      );
      const projectedRecurringShifts = projectRecurringShifts(
        data.recurringShifts,
        window,
      );
      const body = req.method === "HEAD"
        ? null
        : await buildICalendarFeed(data, projectedRecurringShifts, window);

      return new Response(body, {
        status: 200,
        headers: calendarHeaders(requestId),
      });
    } catch (error) {
      const message = error instanceof Error
        ? error.message
        : "Unknown calendar feed error";
      console.error(JSON.stringify({
        scope: "calendar-feed",
        requestId,
        message,
      }));
      return empty(500, requestId);
    }
  };
}
