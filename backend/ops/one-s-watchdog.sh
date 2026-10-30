#!/bin/bash
# Production backend watchdog for one-s. Runs every 5 min from systemd.
# Checks each project's public health, container health, backup freshness,
# and disk usage. Sends one alert email per new problem and one when it clears.
# Alert transport: /srv/backup/alert.env (SMTP_HOST, SMTP_PORT, SMTP_USER,
# SMTP_PASS, ALERT_FROM, ALERT_TO). Without it, problems are only logged.
set -u
STATE=/var/tmp/supabase-watchdog.state
touch "$STATE"
declare -a PROBLEMS=()

check_legacy_bridge() {
  local container state latest
  for container in supabase-auth supabase-db supabase-envoy; do
    state=$(docker inspect -f '{{.State.Status}} {{.State.Health.Status}}' "$container" 2>/dev/null)
    [ "$state" = "running healthy" ] || PROBLEMS+=("tidex upgrade bridge: $container is not healthy")
  done
  source /srv/backup/tidex.conf
  latest=$(ls -t "$DEST"/db-[0-9]*.sql.gz 2>/dev/null | head -1)
  if [ -z "$latest" ] || [ $(( $(date +%s) - $(stat -c %Y "$latest") )) -gt $((26*3600)) ]; then
    PROBLEMS+=("tidex upgrade bridge: nightly backup older than 26h")
  fi
  latest=$(ls -t "$DEST"/db-hourly-*.sql.gz 2>/dev/null | head -1)
  if [ -z "$latest" ] || [ $(( $(date +%s) - $(stat -c %Y "$latest") )) -gt $((3*3600)) ]; then
    PROBLEMS+=("tidex upgrade bridge: hourly backup older than 3h")
  fi
}

check_legacy_bridge
if ! health=$(python3 /srv/tidex/healthcheck.py --legacy-refresh 2>&1); then
  PROBLEMS+=("${health:-tidex: production healthcheck failed without a diagnostic}")
fi
# Paeonia: self-hosted Convex in /srv/paeonia/convex. Backups by paeonia-backup.sh.
code=$(curl -s -m 15 -o /dev/null -w "%{http_code}" https://api.paeonia.no/version)
[ "$code" = "200" ] || PROBLEMS+=("paeonia: api.paeonia.no/version returned $code")
docker ps --format '{{.Names}} {{.Status}}' | grep -q '^convex-backend-1 Up .*(healthy)' || PROBLEMS+=("paeonia: convex-backend-1 is not healthy")
latest=$(ls -t /srv/paeonia/backups/export-[0-9]*.zip 2>/dev/null | head -1)
if [ -z "$latest" ] || [ $(( $(date +%s) - $(stat -c %Y "$latest") )) -gt $((26*3600)) ]; then
  PROBLEMS+=("paeonia: nightly backup older than 26h")
fi
latest=$(ls -t /srv/paeonia/backups/export-hourly-*.zip 2>/dev/null | head -1)
if [ -z "$latest" ] || [ $(( $(date +%s) - $(stat -c %Y "$latest") )) -gt $((3*3600)) ]; then
  PROBLEMS+=("paeonia: hourly backup older than 3h")
fi

# Paeonia capacity: warn while there is still headroom, before requests stall.
# The cgroup counters start over when the container starts. The container keeps its id
# when Docker restarts it after a kill, so the kernel log still matches it.
MEMORY_STATE=/run/supabase-watchdog-paeonia-memory.state
MEMORY_PROBLEM="paeonia: convex-backend-1 memory at or above 70% of its mem_limit for at least 10 minutes"
MEMORY_ACTIVE=0
grep -Fxq "$MEMORY_PROBLEM" "$STATE" && MEMORY_ACTIVE=1
read -r ID STARTED < <(docker inspect -f "{{.Id}} {{.State.StartedAt}}" convex-backend-1 2>/dev/null)
CG=/sys/fs/cgroup/system.slice/docker-$ID.scope
if [ -n "$ID" ] && [ -r "$CG/memory.current" ] && [ "$(cat "$CG/memory.max")" != max ]; then
  NOW=$(date +%s)
  MEMORY_CURRENT=$(cat "$CG/memory.current")
  MEMORY_LIMIT=$(cat "$CG/memory.max")
  INACTIVE_FILE=$(awk '$1 == "inactive_file" { print $2 }' "$CG/memory.stat")
  [[ "$INACTIVE_FILE" =~ ^[0-9]+$ ]] || INACTIVE_FILE=0
  # Match Docker's working set: exclude inactive file cache that Linux can reclaim.
  WORKING_MEMORY=$MEMORY_CURRENT
  (( INACTIVE_FILE < MEMORY_CURRENT )) && WORKING_MEMORY=$(( MEMORY_CURRENT - INACTIVE_FILE ))
  MEMORY_PERCENT=$(( WORKING_MEMORY * 100 / MEMORY_LIMIT ))
  PHASE=
  if [ "$MEMORY_ACTIVE" -eq 0 ] && [ "$MEMORY_PERCENT" -ge 70 ]; then
    PHASE=high
  elif [ "$MEMORY_ACTIVE" -eq 1 ] && (( WORKING_MEMORY * 100 <= MEMORY_LIMIT * 65 )); then
    PHASE=recovery
  fi
  if [ -n "$PHASE" ]; then
    PREVIOUS_INSTANCE= PREVIOUS_PHASE= SINCE= LAST_CHECK=
    [ ! -r "$MEMORY_STATE" ] || read -r PREVIOUS_INSTANCE PREVIOUS_PHASE SINCE LAST_CHECK < "$MEMORY_STATE"
    if [[ "$PREVIOUS_INSTANCE" != "$ID/$STARTED" || "$PREVIOUS_PHASE" != "$PHASE" \
      || ! "$SINCE" =~ ^[0-9]+$ || ! "$LAST_CHECK" =~ ^[0-9]+$ ]] \
      || (( SINCE > LAST_CHECK || LAST_CHECK > NOW || NOW - LAST_CHECK >= 600 )); then
      SINCE=$NOW
    fi
    printf '%s %s %s %s\n' "$ID/$STARTED" "$PHASE" "$SINCE" "$NOW" > "$MEMORY_STATE"
    if [ $(( NOW - SINCE )) -ge 600 ]; then
      if [ "$PHASE" = high ]; then MEMORY_ACTIVE=1; else MEMORY_ACTIVE=0; fi
      : > "$MEMORY_STATE"
    fi
  else
    : > "$MEMORY_STATE"
  fi
  printf 'paeonia memory: working_set=%sMiB (%s%%), total=%sMiB, inactive_file=%sMiB, limit=%sMiB, alert=%s\n' \
    "$(( WORKING_MEMORY / 1048576 ))" "$MEMORY_PERCENT" "$(( MEMORY_CURRENT / 1048576 ))" \
    "$(( INACTIVE_FILE / 1048576 ))" "$(( MEMORY_LIMIT / 1048576 ))" "$MEMORY_ACTIVE"
  awk '$1 == "max" && $2 > 0 { hit = 1 } END { exit !hit }' "$CG/memory.events" \
    && PROBLEMS+=("paeonia: convex-backend-1 reached its mem_limit since it started, so requests stalled")
else
  : > "$MEMORY_STATE"
fi
[ "$MEMORY_ACTIVE" -eq 1 ] && PROBLEMS+=("$MEMORY_PROBLEM")
[ -n "$ID" ] && journalctl -k --since "-6min" -q --no-pager | grep -q "oom-kill:.*docker-$ID.scope" \
  && PROBLEMS+=("paeonia: the kernel killed convex-backend-1 for running out of memory in the last few minutes")
docker logs --since 6m convex-backend-1 2>&1 | grep -q -E "Too many concurrent requests|SystemTimeout|Query execution time out" \
  && PROBLEMS+=("paeonia: convex-backend-1 turned away or timed out requests in the last few minutes")

# Tidex Convex in /srv/tidex/convex. Backups by tidex-convex-backup.sh.
code=$(curl -s -m 15 -o /dev/null -w "%{http_code}" https://convex.tidex.no/version)
[ "$code" = "200" ] || PROBLEMS+=("tidex-convex: convex.tidex.no/version returned $code")
docker ps --format '{{.Names}} {{.Status}}' | grep -q '^tidex-convex-backend-1 Up .*(healthy)' || PROBLEMS+=("tidex-convex: tidex-convex-backend-1 is not healthy")
latest=$(ls -t /srv/tidex/convex-backups/export-[0-9]*.zip 2>/dev/null | head -1)
if [ -z "$latest" ] || [ $(( $(date +%s) - $(stat -c %Y "$latest") )) -gt $((26*3600)) ]; then
  PROBLEMS+=("tidex-convex: nightly backup older than 26h")
fi
latest=$(ls -t /srv/tidex/convex-backups/export-hourly-*.zip 2>/dev/null | head -1)
if [ -z "$latest" ] || [ $(( $(date +%s) - $(stat -c %Y "$latest") )) -gt $((3*3600)) ]; then
  PROBLEMS+=("tidex-convex: hourly backup older than 3h")
fi
USE=$(df --output=pcent / | tail -1 | tr -dc '0-9')
[ "$USE" -ge 85 ] && PROBLEMS+=("one-s: root disk at ${USE}%")
MEMFREE=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
[ "$MEMFREE" -lt 512 ] && PROBLEMS+=("one-s: only ${MEMFREE} MB memory available")

CURRENT=$(printf '%s\n' "${PROBLEMS[@]:-}" | grep -v '^$' | sort)
PREVIOUS=$(sort "$STATE")
send_mail() {  # subject body
  [ -f /srv/backup/alert.env ] || { echo "ALERT (no transport): $1"; return; }
  source /srv/backup/alert.env
  printf 'From: %s\nTo: %s\nSubject: %s\nDate: %s\n\n%s\n' "$ALERT_FROM" "$ALERT_TO" "$1" "$(date -R)" "$2" \
    | curl -s -m 60 --url "smtps://$SMTP_HOST:$SMTP_PORT" --user "$SMTP_USER:$SMTP_PASS" \
        --mail-from "$ALERT_FROM" --mail-rcpt "$ALERT_TO" -T - || echo "alert mail failed"
}
NEW=$(comm -13 <(echo "$PREVIOUS") <(echo "$CURRENT") | grep -v '^$')
CLEARED=$(comm -23 <(echo "$PREVIOUS") <(echo "$CURRENT") | grep -v '^$')
[ -n "$NEW" ] && send_mail "[one-s] Backend watchdog: PROBLEM" "$NEW"
[ -n "$CLEARED" ] && send_mail "[one-s] Backend watchdog: recovered" "$CLEARED"
echo "$CURRENT" > "$STATE"
if [ -n "$CURRENT" ]; then echo "PROBLEMS:"; echo "$CURRENT"; exit 1; fi
echo "all checks passed $(date -Is)"
