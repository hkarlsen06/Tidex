import { getProjectRefFromUrl } from "./utils";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? null;
const projectRef = getProjectRefFromUrl(supabaseUrl);

export const SUPABASE_PROJECT_REF = projectRef;
export const SUPABASE_AUTH_COOKIE_PREFIX = projectRef
  ? `sb-${projectRef}-auth-token`
  : "sb-";

// Backwards compatibility: some helpers may still import NAME. This now represents the prefix.
export const SUPABASE_AUTH_COOKIE_NAME = SUPABASE_AUTH_COOKIE_PREFIX;
