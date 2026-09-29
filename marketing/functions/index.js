const NORWEGIAN_LANGUAGE_CODES = new Set(["nb", "nn", "no"]);
// LOCALE_COOKIE in lib/i18n/config.ts. The language toggle sets it, so a choice made there sticks.
const LOCALE_COOKIE = /(?:^|;\s*)tidex-locale=(no|en)(?:;|$)/;

// Tidex is built around Norwegian pay rules, so Norwegian wins whenever there is a sign of it: Norwegian anywhere in
// Accept-Language, a Norwegian region such as en-NO, or a visitor in Norway. Many Norwegians run their phone in
// English, and Safari then sends only "en-GB" or similar. Everyone else gets English, and the page has a toggle.
export function localeFor(acceptLanguage, country, cookie = "") {
  const chosen = cookie.match(LOCALE_COOKIE)?.[1];
  if (chosen) return chosen;

  const norwegian = acceptLanguage
    .toLowerCase()
    .split(",")
    .map((entry) => entry.trim().split(";"))
    .filter(([, ...params]) => !params.some((param) => /^\s*q=0(\.0*)?\s*$/.test(param)))
    .some(([language]) => {
      const [base, region] = language.split("-");
      return NORWEGIAN_LANGUAGE_CODES.has(base) || region === "no";
    });

  return norwegian || country === "NO" ? "no" : "en";
}

export function onRequest({ request }) {
  const url = new URL(request.url);
  const locale = localeFor(
    request.headers.get("Accept-Language") ?? "",
    request.cf?.country,
    request.headers.get("Cookie") ?? "",
  );
  // "/" becomes "/<locale>/", "/support" becomes "/<locale>/support/".
  url.pathname = `/${locale}${url.pathname.replace(/\/?$/, "/")}`;

  return new Response(null, {
    status: 302,
    headers: {
      Location: url.toString(),
      Vary: "Accept-Language, Cookie",
      "Cache-Control": "no-store",
    },
  });
}
