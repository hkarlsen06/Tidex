// deno-lint-ignore-file no-import-prefix
import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createCalendarFeedHandler, extractRawToken } from "./handler.ts";
import type { CalendarSupabaseClient } from "./types.ts";

const RAW_TOKEN = `tidex_cal_${"a".repeat(64)}`;

class EmptyQuery {
  select(): this {
    return this;
  }
  eq(): this {
    return this;
  }
  is(): this {
    return this;
  }
  gte(): this {
    return this;
  }
  lte(): this {
    return this;
  }
  order(): this {
    return this;
  }
  then<TResult1 = unknown, TResult2 = never>(
    onfulfilled?: ((value: unknown) => TResult1 | PromiseLike<TResult1>) | null,
    onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
  ): PromiseLike<TResult1 | TResult2> {
    return Promise.resolve({ data: [], error: null }).then(
      onfulfilled,
      onrejected,
    );
  }
}

Deno.test("extractRawToken strips trailing .ics before resolver validation", () => {
  assertEquals(
    extractRawToken(
      new Request(
        `https://identity.tidex.no/functions/v1/calendar-feed/${RAW_TOKEN}.ics`,
      ),
    ),
    RAW_TOKEN,
  );
});

Deno.test("handler calls resolver RPC with p_raw_token and returns calendar content for valid tokens", async () => {
  const rpcCalls: Array<
    { functionName: string; args: Record<string, unknown> }
  > = [];
  const client: CalendarSupabaseClient = {
    rpc(functionName: string, args: Record<string, unknown>) {
      rpcCalls.push({ functionName, args });
      return {
        data: [{
          user_id: "user-1",
          content_mode: "events_only",
          locale: "nb",
        }],
        error: null,
      };
    },
    from() {
      return new EmptyQuery();
    },
  };
  const handler = createCalendarFeedHandler({
    supabase: client,
    now: () => new Date("2026-05-15T10:00:00Z"),
  });

  const response = await handler(
    new Request(
      `https://identity.tidex.no/functions/v1/calendar-feed/${RAW_TOKEN}.ics`,
    ),
  );

  assertEquals(response.status, 200);
  assertStringIncludes(
    response.headers.get("Content-Type") ?? "",
    "text/calendar",
  );
  assertStringIncludes(await response.text(), "BEGIN:VCALENDAR");
  assertEquals(rpcCalls, [{
    functionName: "resolve_calendar_subscription_token",
    args: { p_raw_token: RAW_TOKEN },
  }]);
});

Deno.test("handler returns 404 for invalid and resolver-empty tokens", async () => {
  const client: CalendarSupabaseClient = {
    rpc() {
      return { data: [], error: null };
    },
    from() {
      return new EmptyQuery();
    },
  };
  const handler = createCalendarFeedHandler({ supabase: client });

  const invalid = await handler(
    new Request(
      "https://identity.tidex.no/functions/v1/calendar-feed/not-a-token.ics",
    ),
  );
  const unknown = await handler(
    new Request(
      `https://identity.tidex.no/functions/v1/calendar-feed/${RAW_TOKEN}.ics`,
    ),
  );

  assertEquals(invalid.status, 404);
  assertEquals(unknown.status, 404);
});

Deno.test("HEAD returns the same calendar headers without a body", async () => {
  const client: CalendarSupabaseClient = {
    rpc() {
      return {
        data: [{
          user_id: "user-1",
          content_mode: "events_only",
          locale: "en",
        }],
        error: null,
      };
    },
    from() {
      return new EmptyQuery();
    },
  };
  const handler = createCalendarFeedHandler({ supabase: client });
  const response = await handler(
    new Request(
      `https://identity.tidex.no/functions/v1/calendar-feed/${RAW_TOKEN}.ics`,
      {
        method: "HEAD",
      },
    ),
  );

  assertEquals(response.status, 200);
  assertStringIncludes(
    response.headers.get("Content-Type") ?? "",
    "text/calendar",
  );
  assertEquals(await response.text(), "");
});
