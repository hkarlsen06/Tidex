#!/bin/bash
# Checks that production auth still behaves the way the iOS app needs.
# Runs on mdr: /srv/tidex/auth-smoke.sh (called by /srv/backup/watchdog.sh every 5 min).
# Prints one line per problem and exits 1 if there are any. Prints nothing and exits 0 when healthy.
# Install or update: scp supabase/ops/auth-smoke.sh mdr:/srv/tidex/auth-smoke.sh
#
# Every check here maps to a regression from the 2026-09-01 self-hosting move.
set -u
STACK=${STACK:-/srv/tidex/tidex-sb}
URL=${URL:-https://api.tidex.no}
RECOVERY_REDIRECT=tidex://login-callback/recovery

env_value() { grep -m1 "^$1=" "$STACK/.env" | cut -d= -f2-; }
ANON=$(env_value ANON_KEY)
problem() { echo "auth: $*"; FAILED=1; }
FAILED=0

# 1. Providers and signup behaviour the app relies on.
# signUp() in AuthService.swift requires a session straight away, so email autoconfirm must stay on.
settings=$(curl -s -m 15 "$URL/auth/v1/settings" -H "apikey: $ANON")
python3 - "$settings" <<'EOF' || FAILED=1
import json, sys
try:
    s = json.loads(sys.argv[1])
except ValueError:
    print("auth: /settings did not return JSON"); sys.exit(1)
ext = s.get("external", {})
bad = [f"{p} sign-in disabled" for p in ("apple", "google", "email") if not ext.get(p)]
if not s.get("mailer_autoconfirm"):
    bad.append("email autoconfirm is off (new email sign-ups get no session)")
if s.get("disable_signup"):
    bad.append("sign-ups are disabled")
for b in bad:
    print("auth: " + b)
sys.exit(1 if bad else 0)
EOF

# 2. Google native sign-in reaches token verification (a fake token must fail as a bad token, not a disabled provider).
google=$(curl -s -m 15 -X POST "$URL/auth/v1/token?grant_type=id_token" -H "apikey: $ANON" \
  -H "Content-Type: application/json" \
  -d '{"provider":"google","id_token":"eyJhbGciOiJSUzI1NiJ9.eyJpc3MiOiJodHRwczovL2FjY291bnRzLmdvb2dsZS5jb20ifQ.x"}')
case "$google" in *"not enabled"*) problem "Google id_token sign-in is not enabled: $google" ;; esac

# 3. Password reset links keep the app redirect instead of falling back to SITE_URL.
# A bogus token still redirects, to redirect_to if it is allowed and to SITE_URL if not.
location=$(curl -s -m 15 -o /dev/null -w "%{redirect_url}" \
  "$URL/auth/v1/verify?token=smoke-check&type=recovery&redirect_to=$RECOVERY_REDIRECT")
case "$location" in
  "$RECOVERY_REDIRECT"*) ;;
  *) problem "password reset links redirect to '${location%%#*}' instead of $RECOVERY_REDIRECT (check ADDITIONAL_REDIRECT_URLS)" ;;
esac

# 4. Settings that /settings doesn't expose. Compose `environment:` beats env_file, so read the live container.
live_env=$(cd "$STACK" && docker compose exec -T auth env 2>/dev/null)
for want in GOTRUE_SECURITY_MANUAL_LINKING_ENABLED=true GOTRUE_MAILER_AUTOCONFIRM=true; do
  grep -qx "$want" <<<"$live_env" || problem "auth container is missing $want"
done
case "$(grep -m1 '^GOTRUE_SITE_URL=' <<<"$live_env")" in
  GOTRUE_SITE_URL=https://*) ;;
  *) problem "GOTRUE_SITE_URL is not a public https URL: $(grep -m1 '^GOTRUE_SITE_URL=' <<<"$live_env")" ;;
esac

# 5. GoTrue must see real client IPs, not Cloudflare's (MFA verify and rate limits depend on it).
# The requests above went through Cloudflare, so they are in the log.
cf='"remote_addr":"(2400:cb00|2606:4700|2803:f800|2405:b500|2405:8100|2a06:98c0|2c0f:f248|173\.245\.|103\.2[12]\.|103\.31\.|141\.101\.|108\.162\.|190\.93\.|188\.114\.|197\.234\.|198\.41\.|162\.15[89]\.|104\.(1[6-9]|2[0-9]|3[01])\.|172\.(6[4-9]|7[01])\.|131\.0\.72\.)'
logs=$(cd "$STACK" && docker compose logs --since 10m auth 2>&1)
grep -qE "$cf" <<<"$logs" && problem "GoTrue is logging Cloudflare edge IPs as remote_addr (check Caddy trusted_proxies and X-Forwarded-For)"

# 6. Errors that only appear when a provider or security setting is missing.
for pattern in "is not enabled" "Manual linking is disabled" "mfa_ip_address_mismatch" "Unsupported provider"; do
  count=$(grep -c "$pattern" <<<"$logs")
  [ "$count" -gt 0 ] && problem "$count auth log lines with '$pattern' in the last 10 minutes"
done

exit $FAILED
