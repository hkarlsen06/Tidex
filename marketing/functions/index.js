const NORWEGIAN_LANGUAGE_CODES = new Set(["nb", "nn", "no"]);

function parseAcceptLanguage(value) {
  return value
    .split(",")
    .map((entry, index) => {
      const [rawLanguage, ...params] = entry.trim().split(";");
      const language = rawLanguage.toLowerCase();
      const qualityParam = params.find((param) => param.trim().startsWith("q="));
      const quality = qualityParam ? Number.parseFloat(qualityParam.split("=")[1]) : 1;

      return {
        language,
        quality: Number.isFinite(quality) ? quality : 0,
        index,
      };
    })
    .filter((entry) => entry.language && entry.quality > 0)
    .sort((a, b) => b.quality - a.quality || a.index - b.index);
}

function localeFromAcceptLanguage(value) {
  for (const entry of parseAcceptLanguage(value)) {
    const baseLanguage = entry.language.split("-")[0];

    if (NORWEGIAN_LANGUAGE_CODES.has(baseLanguage)) {
      return "no";
    }

    if (baseLanguage === "en") {
      return "en";
    }
  }

  return "en";
}

export function onRequest({ request }) {
  const url = new URL(request.url);
  const locale = localeFromAcceptLanguage(request.headers.get("Accept-Language") ?? "");
  url.pathname = `/${locale}/`;

  return new Response(null, {
    status: 302,
    headers: {
      Location: url.toString(),
      Vary: "Accept-Language",
      "Cache-Control": "no-store",
    },
  });
}
