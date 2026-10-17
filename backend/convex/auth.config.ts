import type { AuthConfig } from "convex/server";

// Convex trusts only Clerk tokens. CLERK_JWT_ISSUER_DOMAIN is the Frontend API URL that
// Clerk shows when you activate its Convex integration. Set it per deployment with
// `convex env set`.
export default {
  providers: [
    {
      domain: process.env.CLERK_JWT_ISSUER_DOMAIN!,
      applicationID: "convex",
    },
  ],
} satisfies AuthConfig;
