import { NextResponse } from "next/server";

/**
 * Apple App Site Association (AASA) file for iOS Universal Links
 *
 * This enables iOS to recognize app.tidex.no as a universal link domain,
 * allowing the native Capacitor app to intercept navigation to /auth/* paths
 * (e.g., after OAuth redirects from Supabase).
 *
 * @see https://developer.apple.com/documentation/xcode/supporting-associated-domains
 */
export function GET() {
  const aasa = {
    applinks: {
      apps: [],
      details: [
        {
          appID: "48ZSLD4RMP.no.tidex.app",
          paths: ["/auth/callback*", "/auth/*"],
        },
      ],
    },
  };

  return NextResponse.json(aasa, {
    headers: {
      "Content-Type": "application/json",
      // Ensure iOS can cache this for a reasonable time
      "Cache-Control": "public, max-age=86400",
    },
  });
}
