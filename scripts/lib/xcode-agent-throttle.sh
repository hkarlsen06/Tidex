# shellcheck shell=bash
# Sourced by scripts/xcode-build-agent.sh and scripts/xcode-test-agent.sh.
#
# Keeps agent-driven xcodebuild runs from saturating the Mac:
#   - one wrapper-driven xcodebuild at a time across every repo on this
#     machine (shared lock in /tmp), so parallel agents queue instead of
#     competing for cores
#   - lower CPU priority (nice) and half the CPUs for compile jobs, so the
#     desktop and Xcode stay responsive
#   - tests run without parallel simulator clones, and UI test targets are
#     skipped unless a run asks for them
#
# Must stay compatible with macOS /bin/bash 3.2 (no mapfile, no ${x,,}).
#
# Environment overrides:
#   XCODE_AGENT_LOCK_DIR               lock path (default /tmp/xcode-agent.lock)
#   XCODE_AGENT_NO_LOCK=1              skip the machine-wide lock
#   XCODE_AGENT_NICE=N                 nice level, 0 disables (default 10)
#   XCODE_AGENT_JOBS=N                 xcodebuild -jobs (default: half the logical CPUs)
#   XCODE_TEST_AGENT_PARALLEL=1        allow Xcode parallel testing (clones simulators)
#   XCODE_TEST_AGENT_INCLUDE_UI_TESTS=1  run *UITests targets in an unfiltered run

XA_LOCK_DIR="${XCODE_AGENT_LOCK_DIR:-/tmp/xcode-agent.lock}"
XA_LOCK_HELD=0
XA_NICE="${XCODE_AGENT_NICE:-10}"
XA_ARGS=()
XA_PREFIX=()

xa_default_jobs() {
  local n
  n="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 8)"
  # Half the logical CPUs (at least 2): builds take longer, but the rest
  # of the Mac stays usable while agents keep the build queue busy.
  if [ "$n" -ge 4 ]; then
    echo $((n / 2))
  else
    echo 2
  fi
}
XA_JOBS="${XCODE_AGENT_JOBS:-$(xa_default_jobs)}"

if [ "$XA_NICE" != "0" ]; then
  XA_PREFIX=(nice -n "$XA_NICE")
fi

# Turn INT/TERM/HUP into a normal exit so the caller's EXIT trap runs,
# which stops xcodebuild and releases the lock instead of orphaning them.
xa_install_signal_traps() {
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
}

xa_log() {
  echo "[$(basename "$0" .sh)] $*" >&2
}

xa_acquire_lock() {
  if [ "${XCODE_AGENT_NO_LOCK:-0}" = "1" ]; then
    return 0
  fi

  local waited=0 owner pid mtime now
  while ! mkdir "$XA_LOCK_DIR" 2>/dev/null; do
    owner="$(cat "$XA_LOCK_DIR/owner" 2>/dev/null || true)"
    pid="${owner%% *}"

    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      xa_log "removing stale xcodebuild lock left by pid $pid"
      rm -rf "$XA_LOCK_DIR"
      continue
    fi

    if [ -z "$owner" ]; then
      # Lock dir without an owner file: either another wrapper is between
      # mkdir and writing the file, or it died there. Clear it after 60s.
      now="$(date +%s)"
      mtime="$(stat -f %m "$XA_LOCK_DIR" 2>/dev/null || true)"
      case "$mtime" in
        ''|*[!0-9]*) mtime="$(stat -c %Y "$XA_LOCK_DIR" 2>/dev/null || true)" ;;
      esac
      case "$mtime" in
        ''|*[!0-9]*) mtime="$now" ;;
      esac
      if [ $((now - mtime)) -gt 60 ]; then
        rm -rf "$XA_LOCK_DIR"
        continue
      fi
    fi

    if [ $((waited % 20)) -eq 0 ]; then
      xa_log "waiting for another agent's xcodebuild to finish (${owner:-starting}); ${waited}s waited"
    fi
    sleep 2
    waited=$((waited + 2))
  done

  echo "$$ $(basename "$(pwd)") $(basename "$0" .sh) since $(date +%H:%M:%S)" >"$XA_LOCK_DIR/owner"
  XA_LOCK_HELD=1
  if [ "$waited" -gt 0 ]; then
    xa_log "xcodebuild lock acquired after ${waited}s"
  fi
}

xa_release_lock() {
  if [ "$XA_LOCK_HELD" = "1" ]; then
    rm -rf "$XA_LOCK_DIR"
    XA_LOCK_HELD=0
  fi
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
