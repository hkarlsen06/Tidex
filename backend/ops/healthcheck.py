#!/usr/bin/env python3
"""Check production Convex, Clerk and retained migration routes without real sessions."""

import argparse
import json
from pathlib import Path
import urllib.error
import urllib.request


def request(url, data=None, headers=None):
    req = urllib.request.Request(url, data=data, headers={"User-Agent": "Tidex healthcheck", **(headers or {})})
    try:
        response = urllib.request.urlopen(req, timeout=15)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        return response.status, response.read(), response.headers


def convex():
    status, body, _ = request("https://convex.tidex.no/version")
    assert status == 200 and body.strip(), f"Convex API returned HTTP {status}"
    status, body, headers = request("https://actions.tidex.no/health")
    assert status == 200 and json.loads(body) == {"ok": True}, f"Convex HTTP/database health failed with HTTP {status}"
    assert "no-store" in headers.get("Cache-Control", ""), "Convex health response permits caching"


def clerk():
    status, body, _ = request("https://clerk.tidex.no/v1/environment?_is_native=true")
    assert status == 200, f"Clerk configuration returned HTTP {status}"
    settings = json.loads(body)["user_settings"]
    email = settings["attributes"]["email_address"]
    assert email["enabled"] and not email["required"] and email["verify_at_sign_up"], "Clerk email requirements changed"
    for provider in ("oauth_apple", "oauth_google"):
        assert settings["social"][provider]["enabled"] and settings["social"][provider]["authenticatable"], f"Clerk {provider} sign-in disabled"


def calendars():
    for host in ("actions.tidex.no", "api.tidex.no", "identity.tidex.no"):
        prefix = "" if host == "actions.tidex.no" else "/functions/v1"
        status, _, headers = request(f"https://{host}{prefix}/calendar-feed/healthcheck-invalid-token.ics")
        assert status == 404 and headers.get("x-calendar-feed-request-id"), f"{host} did not reach the Convex calendar handler, HTTP {status}"


def legacy_refresh():
    lines = Path("/srv/tidex/tidex-sb/.env").read_text().splitlines()
    values = dict(line.split("=", 1) for line in lines if "=" in line and not line.startswith("#"))
    for host in ("api.tidex.no", "identity.tidex.no"):
        status, body, _ = request(
            f"https://{host}/auth/v1/token?grant_type=refresh_token",
            data=b'{"refresh_token":"aftercare-routing-probe"}',
            headers={"Content-Type": "application/json", "apikey": values["ANON_KEY"].strip('"')},
        )
        assert status == 400 and json.loads(body).get("msg") == "Refresh token is not valid", f"{host} did not reach GoTrue refresh, HTTP {status}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--legacy-refresh", action="store_true", help="Check GoTrue while the upgrade bridge is retained")
    args = parser.parse_args()
    checks = [convex, clerk, calendars]
    if args.legacy_refresh:
        checks.append(legacy_refresh)
    failed = False
    for check in checks:
        try:
            check()
        except (AssertionError, OSError, ValueError, KeyError, TypeError) as error:
            print(f"tidex {check.__name__}: {error}")
            failed = True
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
