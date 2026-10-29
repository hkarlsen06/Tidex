import config from "../public/app-config.json";

// Remove this exception after 3.1.0 is available in the App Store.
// It only controls the maintenance screen. Backend authorization is unchanged.
export function onRequest({ request }) {
  const approvedBuild = /^Tidex\/20261028\.1856 CFNetwork\//.test(
    request.headers.get("User-Agent") ?? "",
  );

  return Response.json(approvedBuild ? { ...config, maintenance: false } : config, {
    headers: {
      "Cache-Control": "no-store",
      Vary: "User-Agent",
    },
  });
}
