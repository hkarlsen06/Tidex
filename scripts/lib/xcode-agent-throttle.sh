# shellcheck shell=bash
# Sourced by scripts/xcode-build-agent.sh and scripts/xcode-test-agent.sh.
#
# Xcode work on this Mac goes through ios-agent, the host controller. It
# queues compiles from every repo first come, first served, and runs them with
# six jobs at a lower CPU priority. `ios-agent status` shows the queue. A
# machine without ios-agent, such as CI, runs xcodebuild directly.
#
# Tests run without parallel simulator clones, and UI test targets are skipped
# unless a run asks for them.
#
# Must stay compatible with macOS /bin/bash 3.2 (no mapfile, no ${x,,}).
#
# Environment overrides, the first two read by ios-agent too:
#   XCODE_AGENT_NICE=N                 nice level, 0 disables (default 10)
#   XCODE_AGENT_JOBS=N                 xcodebuild -jobs (default 6)
#   XCODE_TEST_AGENT_PARALLEL=1        allow Xcode parallel testing (clones simulators)
#   XCODE_TEST_AGENT_INCLUDE_UI_TESTS=1  run *UITests targets in an unfiltered run

XA_NICE="${XCODE_AGENT_NICE:-10}"
XA_JOBS="${XCODE_AGENT_JOBS:-6}"
XA_ARGS=()

# Turn INT/TERM/HUP into a normal exit so the caller's EXIT trap runs,
# which stops xcodebuild instead of orphaning it.
xa_install_signal_traps() {
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
}

xa_log() {
  echo "[$(basename "$0" .sh)] $*" >&2
}

xa_stop_xcodebuild() {
  local pid="${1:-}"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
}

# xa_configure <build|analyze|archive|exportArchive|test> [user xcodebuild args...]
# Fills XA_ARGS with the throttling flags for that action.
xa_configure() {
  local mode="$1"
  shift
  XA_ARGS=()

  case "$mode" in
    exportArchive) return 0 ;;
  esac

  XA_ARGS=(-jobs "$XA_JOBS")

  if [ "$mode" != "test" ]; then
    return 0
  fi

  if [ "${XCODE_TEST_AGENT_PARALLEL:-0}" != "1" ]; then
    XA_ARGS+=(-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1)
  fi

  if [ "${XCODE_TEST_AGENT_INCLUDE_UI_TESTS:-0}" = "1" ]; then
    return 0
  fi

  local arg
  for arg in "$@"; do
    case "$arg" in
      -only-testing*|-testPlan*|-skip-testing*UITests*) return 0 ;;
    esac
  done

  local dir skipped=""
  for dir in ios/*UITests; do
    [ -d "$dir" ] || continue
    XA_ARGS+=("-skip-testing:$(basename "$dir")")
    skipped="$skipped $(basename "$dir")"
  done
  if [ -n "$skipped" ]; then
    xa_log "unfiltered run: skipping UI test targets:$skipped (XCODE_TEST_AGENT_INCLUDE_UI_TESTS=1 to include)"
  fi
}

xa_physical_destination() {
  if [ -z "$XA_IOS_AGENT" ]; then
    xa_log "ios-agent is unavailable; using a shared simulator (set XCODE_TEST_AGENT_DESTINATION for an explicit destination)"
    return 0
  fi
  local destination
  if destination="$("$XA_IOS_AGENT" physical-destination)"; then
    printf '%s\n' "$destination"
  else
    xa_log "device discovery failed; using a shared simulator"
  fi
}

# xa_start_heartbeat <what> reports every HEARTBEAT_INTERVAL seconds on the
# xcodebuild in XCODEBUILD_PID: its place in the queue while it waits, then
# how long it has run.
xa_start_heartbeat() {
  local start_time
  start_time="$(date +%s)"
  xa_log "$1 started; heartbeat every ${HEARTBEAT_INTERVAL}s"

  (
    while kill -0 "$XCODEBUILD_PID" 2>/dev/null; do
      sleep "$HEARTBEAT_INTERVAL"
      kill -0 "$XCODEBUILD_PID" 2>/dev/null || exit 0

      now="$(date +%s)"
      queued_for="$(xa_queued_for)"
      if [ -n "$queued_for" ]; then
        xa_log "queued for $queued_for ($((now - start_time))s waited)"
      else
        xa_log "alive: $1 still running ($((now - $(xa_started "$start_time")))s elapsed)"
      fi
    done
  ) &
  XA_HEARTBEAT_PID=$!
}

xa_stop_heartbeat() {
  if [ -n "${XA_HEARTBEAT_PID:-}" ]; then
    local sleeping
    sleeping="$(pgrep -P "$XA_HEARTBEAT_PID" || true)"
    kill "$XA_HEARTBEAT_PID" 2>/dev/null || true
    wait "$XA_HEARTBEAT_PID" 2>/dev/null || true
    # Its sleep would otherwise keep our output open, and a reader on a pipe
    # would wait for it.
    # shellcheck disable=SC2086
    [ -z "$sleeping" ] || kill $sleeping 2>/dev/null || true
    XA_HEARTBEAT_PID=""
  fi
}

# Prints what ios-agent itself said about a failed run, such as why it
# stopped it. Its output goes to the xcodebuild log with everything else.
xa_controller_messages() {
  grep '^\[ios-agent\]' "$1" | grep -v 'queued for' >&2 || true
}

if ! [[ "$XA_JOBS" =~ ^[1-9][0-9]*$ ]]; then
  echo "XCODE_AGENT_JOBS must be a positive integer" >&2
  exit 2
fi

# A git client started from the Dock runs the pre-push hook without
# ~/.local/bin on PATH, and that build must queue too.
XA_IOS_AGENT="$(command -v ios-agent || true)"
if [ -z "$XA_IOS_AGENT" ] && [ -x "$HOME/.local/bin/ios-agent" ]; then
  XA_IOS_AGENT="$HOME/.local/bin/ios-agent"
fi

# Run xcodebuild as "${XA_XCODEBUILD[@]}" <arguments> &, so that $! is the
# process to stop.
if [ -n "$XA_IOS_AGENT" ]; then
  XA_XCODEBUILD=("$XA_IOS_AGENT" xcodebuild)
elif [ "$XA_NICE" != "0" ]; then
  XA_XCODEBUILD=(nice -n "$XA_NICE" xcodebuild)
else
  XA_XCODEBUILD=(xcodebuild)
fi

# ios-agent keeps one line here for the xcodebuild it is running for us:
# "queued<TAB>what it waits for", then "running<TAB>start time".
XA_STATUS_FILE="$(mktemp "${TMPDIR:-/tmp}/xcode-agent-status.XXXXXX")"
export IOS_AGENT_STATUS_FILE="$XA_STATUS_FILE"

# Prints what the current xcodebuild waits for, or nothing once it runs.
xa_queued_for() {
  local state detail
  IFS=$'\t' read -r state detail <"$XA_STATUS_FILE" || true
  if [ "$state" = queued ]; then
    echo "$detail"
  fi
}

# xa_started <fallback> prints when the last xcodebuild left the queue: now if
# it never did, and the fallback when no controller reported.
xa_started() {
  local state detail
  IFS=$'\t' read -r state detail <"$XA_STATUS_FILE" || true
  case "$state" in
    running) echo "$detail" ;;
    queued) date +%s ;;
    *) echo "$1" ;;
  esac
}
