import { withSupabase } from "@supabase/server";
import { createCalendarFeedHandler } from "./handler.ts";

export default {
  fetch: withSupabase<any>(
    { auth: "none", cors: "disabled" },
    (request, { supabaseAdmin }) =>
      createCalendarFeedHandler({ supabase: supabaseAdmin })(request),
  ),
};
