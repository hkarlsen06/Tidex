#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "--devices" ]; then
  if command -v ios-agent >/dev/null 2>&1; then
    exec ios-agent devices --json
  fi
  echo "ios-agent is unavailable; use XCODE_TEST_AGENT_DESTINATION for an explicit destination" >&2
  exit 2
fi

# The host shim queues both invocations. Audited suites prefer the approved
# spare returned by ios-agent; full suites and UI tests use the simulator.
# An explicit destination is preserved. Physical app data is never reset.

MODE="text"
EXTRA_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --json)
      MODE="json"
      shift
      ;;
    --)
      shift
      EXTRA_ARGS+=("$@")
      break
      ;;
    *)
      EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

DEFAULT_HEARTBEAT_INTERVAL=20
MIN_HEARTBEAT_INTERVAL=15
HEARTBEAT_INTERVAL="${XCODE_TEST_AGENT_HEARTBEAT_INTERVAL:-$DEFAULT_HEARTBEAT_INTERVAL}"
PROJECT_PATH="${XCODE_TEST_AGENT_PROJECT_PATH:-ios/Tidex.xcodeproj}"
SCHEME_NAME="${XCODE_TEST_AGENT_SCHEME:-App}"
BUILD_BUNDLE="${TMPDIR:-/tmp}/tidex-build-for-testing-$(date +%s)-$$.xcresult"
RESULT_BUNDLE="${TMPDIR:-/tmp}/tidex-test-$(date +%s)-$$.xcresult"
LOG_FILE="$(mktemp "${TMPDIR:-/tmp}/tidex-test-log.XXXXXX")"
JSON_FILE="$(mktemp "${TMPDIR:-/tmp}/tidex-test-json.XXXXXX")"
PARSED_FILE="$(mktemp "${TMPDIR:-/tmp}/tidex-test-parsed.XXXXXX")"
SIMULATOR_FILE="$(mktemp "${TMPDIR:-/tmp}/tidex-test-simulator.XXXXXX")"
XCODEBUILD_PID=""
HEARTBEAT_PID=""
KEEP_ARTIFACTS="${XCODE_TEST_AGENT_KEEP_ARTIFACTS:-0}"

if ! [[ "$HEARTBEAT_INTERVAL" =~ ^[0-9]+$ ]]; then
  HEARTBEAT_INTERVAL="$DEFAULT_HEARTBEAT_INTERVAL"
elif [ "$HEARTBEAT_INTERVAL" -lt "$MIN_HEARTBEAT_INTERVAL" ]; then
  HEARTBEAT_INTERVAL="$MIN_HEARTBEAT_INTERVAL"
fi

# Shuts down a simulator of the destination that this run booted. Shared
# simulators stay booted.
shutdown_test_simulator() {
  if [ "${SHUTDOWN_TEST_SIMULATOR:-0}" = "1" ]; then
    xcrun simctl shutdown "$TEST_SIMULATOR_UDID" >/dev/null 2>&1 || true
    SHUTDOWN_TEST_SIMULATOR=0
  fi
}

# In phase 2, XCODEBUILD_PID can be scripts/lock, with xcodebuild as its child.
stop_xcodebuild() {
  if [ -n "${XCODEBUILD_PID:-}" ]; then
    pkill -TERM -P "$XCODEBUILD_PID" 2>/dev/null || true
  fi
  xa_stop_xcodebuild "${XCODEBUILD_PID:-}"
}

cleanup() {
  stop_xcodebuild
  xa_release_lock
  shutdown_test_simulator
  if [ -n "${HEARTBEAT_PID:-}" ]; then
    kill "$HEARTBEAT_PID" 2>/dev/null || true
    wait "$HEARTBEAT_PID" 2>/dev/null || true
  fi
  rm -f "$SIMULATOR_FILE"
  if [ "$KEEP_ARTIFACTS" = "1" ]; then
    return
  fi
  rm -f "$LOG_FILE" "$JSON_FILE" "$PARSED_FILE"
  rm -rf "$BUILD_BUNDLE" "$RESULT_BUNDLE"
}
trap cleanup EXIT
# shellcheck source=lib/xcode-agent-throttle.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/xcode-agent-throttle.sh"
xa_install_signal_traps

start_heartbeat() {
  local start_time
  start_time="$(date +%s)"
  echo "[xcode-test-agent] $1 started; heartbeat every ${HEARTBEAT_INTERVAL}s" >&2

  (
    while kill -0 "$XCODEBUILD_PID" 2>/dev/null; do
      sleep "$HEARTBEAT_INTERVAL"
      kill -0 "$XCODEBUILD_PID" 2>/dev/null || exit 0

      local now elapsed
      now="$(date +%s)"
      elapsed=$((now - start_time))
      echo "[xcode-test-agent] alive: $1 still running (${elapsed}s elapsed)" >&2
    done
  ) &
  HEARTBEAT_PID=$!
}

stop_heartbeat() {
  if [ -n "${HEARTBEAT_PID:-}" ]; then
    kill "$HEARTBEAT_PID" 2>/dev/null || true
    wait "$HEARTBEAT_PID" 2>/dev/null || true
    HEARTBEAT_PID=""
  fi
}

# An ongoing shift leaves a Live Activity on the simulator, and after xcodebuild
# reinstalls the app, liveactivitiesd relaunches Tidex in the background.
# xcodebuild then attaches to that launch, which has no XCTest injection, and
# fails with "test runner hung before establishing connection" or "failed to
# launch no.tidex.app". So every run on a simulator first uninstalls Tidex
# there, which also removes its Live Activities and any state left by earlier
# runs. On a shared simulator that happens under its lock.

# Prints "<udid>|<name>" of the available simulator that an xcodebuild
# destination names by id or name. Prints nothing for a physical device, where
# uninstalling would delete the user's data.
destination_simulator() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
# Read all of stdin before any exit, or simctl dies of SIGPIPE and pipefail
# stops the wrapper.
runtimes = json.load(sys.stdin)["devices"]
spec = {}
for part in sys.argv[1].split(","):
    key, _, value = part.partition("=")
    spec[key.strip()] = value.strip()
if spec.get("platform") != "iOS Simulator":
    sys.exit()
for devices in runtimes.values():
    for device in devices:
        if device["udid"] == spec.get("id") or device["name"] == spec.get("name"):
            print(device["udid"] + "|" + device["name"])
            sys.exit()
' "$1"
}

# The simulator lock phase 2 takes: `simulator` for any shared simulator, one
# shared simulator's name, or nothing. TEST_SIMULATOR_UDID is a simulator
# outside the pool, which phase 2 resets without a lock.
SIMULATOR_LOCK=simulator
TEST_SIMULATOR_UDID=""
SHUTDOWN_TEST_SIMULATOR=0
DESTINATION="${XCODE_TEST_AGENT_DESTINATION:-}"
AUTO_DEVICE=1
SAFE_SELECTION=0
UNSAFE_SELECTION=0
EXPECT_DESTINATION=0
for arg in ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}; do
  if [ "$EXPECT_DESTINATION" = "1" ]; then
    [ -n "$DESTINATION" ] || DESTINATION="$arg"
    EXPECT_DESTINATION=0
    continue
  fi
  case "$arg" in
    -destination) AUTO_DEVICE=0; EXPECT_DESTINATION=1 ;;
    -only-testing:TidexAppTests/ISO8601TimestampTests|-only-testing:TidexAppTests/ISO8601TimestampTests/*|-only-testing:TidexAppTests/AppDeepLinkResolverTests|-only-testing:TidexAppTests/AppDeepLinkResolverTests/*) SAFE_SELECTION=1 ;;
    -only-testing*|-skip-testing*|-testPlan*|-xctestrun*) AUTO_DEVICE=0; UNSAFE_SELECTION=1 ;;
  esac
done
if [ "$SAFE_SELECTION" = "0" ]; then
  AUTO_DEVICE=0
fi
if [ "${INCLUDE_UI:-0}" = "1" ] || [ "${XCODE_TEST_AGENT_INCLUDE_UI_TESTS:-0}" = "1" ]; then
  AUTO_DEVICE=0
  UNSAFE_SELECTION=1
fi
if [ -z "$DESTINATION" ] && [ "$AUTO_DEVICE" = "1" ]; then
  DESTINATION="$(xa_physical_destination)"
fi
BUILD_DESTINATION='generic/platform=iOS Simulator'
case "$DESTINATION" in
  platform=iOS,*|platform=iOS)
    if [ "$SAFE_SELECTION" != "1" ] || [ "$UNSAFE_SELECTION" = "1" ]; then
      echo "Physical tests require audited device-safe -only-testing selections; use a simulator for other suites" >&2
      exit 2
    fi
    BUILD_DESTINATION='generic/platform=iOS' ;;
esac
if [ -n "$DESTINATION" ]; then
  SIMULATOR_LOCK=""
  if ! DESTINATION_SIMULATOR="$(destination_simulator "$DESTINATION" 2>/dev/null)"; then
    xa_log "could not list simulators; running on $DESTINATION without resetting it"
    DESTINATION_SIMULATOR=""
  fi
  if [ -n "$DESTINATION_SIMULATOR" ]; then
    case "${DESTINATION_SIMULATOR#*|}" in
      'Shared iPhone'|'Shared iPhone 2'|'Shared iPhone 3') SIMULATOR_LOCK="${DESTINATION_SIMULATOR#*|}" ;;
      *) TEST_SIMULATOR_UDID="${DESTINATION_SIMULATOR%%|*}" ;;
    esac
  fi
fi

reset_test_simulator() {
  [ -n "$TEST_SIMULATOR_UDID" ] || return 0
  # Captured rather than piped to grep -q, which under pipefail can fail the
  # pipeline with SIGPIPE and shut down a simulator that was already booted.
  case "$(xcrun simctl list devices booted)" in
    *"$TEST_SIMULATOR_UDID"*) ;;
    *) SHUTDOWN_TEST_SIMULATOR=1 ;;
  esac
  xa_log "resetting simulator $TEST_SIMULATOR_UDID: uninstalling no.tidex.app"
  xcrun simctl bootstatus "$TEST_SIMULATOR_UDID" -b >/dev/null
  xcrun simctl uninstall "$TEST_SIMULATOR_UDID" no.tidex.app >/dev/null 2>&1 || true
}

# The build gets the extra arguments without their destinations.
BUILD_EXTRA_ARGS=()
SKIP_NEXT=0
for arg in ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}; do
  if [ "$SKIP_NEXT" = "1" ]; then
    SKIP_NEXT=0
  elif [ "$arg" = "-destination" ]; then
    SKIP_NEXT=1
  else
    BUILD_EXTRA_ARGS+=("$arg")
  fi
done

QUEUED=0
COMPILED=0
TESTED=0
SIMULATOR=""

set +e
xa_configure build-for-testing
QUEUE_START="$(date +%s)"
xa_acquire_lock
COMPILE_START="$(date +%s)"
QUEUED=$((COMPILE_START - QUEUE_START))
${XA_PREFIX[@]+"${XA_PREFIX[@]}"} xcodebuild ${XA_ARGS[@]+"${XA_ARGS[@]}"} \
  -quiet \
  -resultBundlePath "$BUILD_BUNDLE" \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_NAME" \
  -destination "$BUILD_DESTINATION" \
  build-for-testing \
  ${BUILD_EXTRA_ARGS[@]+"${BUILD_EXTRA_ARGS[@]}"} >"$LOG_FILE" 2>&1 &
XCODEBUILD_PID=$!
start_heartbeat build
wait "$XCODEBUILD_PID"
EXIT_CODE=$?
XCODEBUILD_PID=""
stop_heartbeat
xa_release_lock
COMPILED=$(($(date +%s) - COMPILE_START))

PARSED_BUNDLE="$BUILD_BUNDLE"
if [ "$EXIT_CODE" -eq 0 ]; then
  PARSED_BUNDLE="$RESULT_BUNDLE"
  xa_configure test ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
  TEST_ARGS=(
    ${XA_ARGS[@]+"${XA_ARGS[@]}"}
    -quiet
    -resultBundlePath "$RESULT_BUNDLE"
    -project "$PROJECT_PATH"
    -scheme "$SCHEME_NAME"
    test-without-building
    ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
  )
  TEST_QUEUE_START="$(date +%s)"
  if [ -n "$SIMULATOR_LOCK" ]; then
    # Under the simulator's lock: note when it was taken and which simulator
    # it is, reset it, then test on it.
    "$(dirname "$0")/lock" run "$SIMULATOR_LOCK" -- sh -c '
      log="$1"
      shift
      printf "%s|%s\n" "$(date +%s)" "$AGENT_SIMULATOR_NAME" >"$0"
      echo "[xcode-test-agent] resetting $AGENT_SIMULATOR_NAME: uninstalling no.tidex.app" >&2
      xcrun simctl uninstall "$AGENT_SIMULATOR_UDID" no.tidex.app >/dev/null 2>&1
      exec "$@" -destination "platform=iOS Simulator,id=$AGENT_SIMULATOR_UDID" >>"$log" 2>&1
    ' "$SIMULATOR_FILE" "$LOG_FILE" \
      ${XA_PREFIX[@]+"${XA_PREFIX[@]}"} xcodebuild "${TEST_ARGS[@]}" &
  else
    reset_test_simulator
    TEST_QUEUE_START="$(date +%s)"
    printf "%s|\n" "$TEST_QUEUE_START" >"$SIMULATOR_FILE"
    ${XA_PREFIX[@]+"${XA_PREFIX[@]}"} xcodebuild "${TEST_ARGS[@]}" \
      -destination "$DESTINATION" >>"$LOG_FILE" 2>&1 &
  fi
  XCODEBUILD_PID=$!
  start_heartbeat tests
  wait "$XCODEBUILD_PID"
  EXIT_CODE=$?
  XCODEBUILD_PID=""
  stop_heartbeat
  shutdown_test_simulator
  IFS='|' read -r TEST_START SIMULATOR <"$SIMULATOR_FILE" || true
  TEST_START="${TEST_START:-$(date +%s)}"
  QUEUED=$((QUEUED + TEST_START - TEST_QUEUE_START))
  TESTED=$(($(date +%s) - TEST_START))
  if [ -n "$SIMULATOR" ]; then
    DESTINATION="platform=iOS Simulator,name=$SIMULATOR"
  fi
fi
set -e

STATUS="SUCCESS"
if [ "$EXIT_CODE" -ne 0 ]; then
  STATUS="FAILURE"
fi

XCRESULT_OK=0
if [ -d "$PARSED_BUNDLE" ]; then
  set +e
  xcrun xcresulttool get --legacy --format json --path "$PARSED_BUNDLE" >"$JSON_FILE" 2>/dev/null
  XCRESULT_EXIT=$?
  set -e
  if [ "$XCRESULT_EXIT" -eq 0 ] && [ -s "$JSON_FILE" ]; then
    XCRESULT_OK=1
  fi
fi

python3 - "$MODE" "$STATUS" "$JSON_FILE" "$PARSED_FILE" "$LOG_FILE" "$XCRESULT_OK" \
  "$DESTINATION" "$SCHEME_NAME" "$PARSED_BUNDLE" "$KEEP_ARTIFACTS" \
  "$QUEUED" "$COMPILED" "$TESTED" "$SIMULATOR" <<'PY'
import json
import sys
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse

(
    mode,
    status,
    json_path,
    parsed_path,
    log_path,
    xcresult_ok,
    destination,
    scheme_name,
    result_bundle_path,
    keep_artifacts,
    queued,
    compiled,
    tested,
    simulator,
) = sys.argv[1:15]
xcresult_ok = xcresult_ok == "1"
keep_artifacts = keep_artifacts == "1"

warnings = []
errors = []
test_failures = []
tests_count = None
tests_failed = None

def add_unique(target, value):
    value = (value or "").strip()
    if value and value not in target:
        target.append(value)

def unwrap(value):
    if isinstance(value, dict) and "_value" in value:
        return value["_value"]
    return value

def node_type_name(node):
    node_type = node.get("_type")
    if isinstance(node_type, dict):
        return unwrap(node_type.get("_name")) or ""
    return ""

def normalize_location(raw_location):
    if not raw_location:
        return ""

    parsed = urlparse(raw_location)
    if parsed.scheme != "file":
        return raw_location

    path = unquote(parsed.path)
    query = parse_qs(parsed.fragment)
    line = query.get("StartingLineNumber", [None])[0]
    if line:
        return f"{path}:{line}"
    return path

def build_issue_line(message, test_case_name="", location=""):
    prefix = test_case_name.strip()
    normalized_location = normalize_location(location)

    if prefix and normalized_location:
        return f"{prefix} [{normalized_location}]: {message}"
    if prefix:
        return f"{prefix}: {message}"
    if normalized_location:
        return f"{normalized_location}: {message}"
    return message

def extract_from_xcresult(data):
    global tests_count, tests_failed
    issue_categories = {
        "testWarningSummaries": "warning",
        "warningSummaries": "warning",
        "analyzerWarningSummaries": "warning",
        "testFailureSummaries": "failure",
        "errorSummaries": "error",
    }

    def walk(node, issue_category=""):
        global tests_count, tests_failed

        if isinstance(node, dict):
            summary_type = str(node_type_name(node))
            issue_type = str(unwrap(node.get("issueType")) or "").lower()
            message = unwrap(node.get("message")) or ""
            test_case_name = str(unwrap(node.get("testCaseName")) or "")
            location = ""

            docloc = node.get("documentLocationInCreatingWorkspace")
            if isinstance(docloc, dict):
                location = unwrap(docloc.get("url")) or ""

            if issue_type and message:
                line = build_issue_line(message, test_case_name=test_case_name, location=location)
                if issue_category == "warning" or "warning" in issue_type:
                    add_unique(warnings, line)
                elif summary_type == "TestFailureIssueSummary" or issue_category == "failure":
                    add_unique(test_failures, line)
                    add_unique(errors, line)
                elif issue_category == "error" or "error" in issue_type:
                    add_unique(errors, line)

            metrics = node.get("metrics")
            # Invocation totals already aggregate actions; build metrics may be zero.
            if node is data and isinstance(metrics, dict):
                tests_count_value = unwrap(metrics.get("testsCount"))
                tests_failed_value = unwrap(metrics.get("testsFailedCount"))
                if tests_count_value is not None:
                    try:
                        tests_count = int(tests_count_value)
                    except Exception:
                        pass
                if tests_failed_value is not None:
                    try:
                        tests_failed = int(tests_failed_value)
                    except Exception:
                        pass

            for key, value in node.items():
                walk(value, issue_categories.get(key, issue_category))

        elif isinstance(node, list):
            for item in node:
                walk(item, issue_category)

    walk(data)

if xcresult_ok:
    try:
        with open(json_path, "r", encoding="utf-8") as file:
            data = json.load(file)
        extract_from_xcresult(data)
    except Exception:
        pass

if not warnings or not errors or not test_failures:
    text = Path(log_path).read_text(encoding="utf-8", errors="replace")

    in_testing_failed = False
    for line in text.splitlines():
        normalized_line = line.strip()
        # xcodebuild lists why testing could not start under "Testing failed:".
        if normalized_line == "Testing failed:":
            in_testing_failed = True
            continue
        if in_testing_failed:
            if line.startswith(("\t", " ")) and normalized_line:
                add_unique(errors, normalized_line)
                continue
            in_testing_failed = False
        if " warning: " in line:
            add_unique(warnings, line)
        elif " error: " in line:
            add_unique(errors, line)
        elif normalized_line.startswith("Test Case '-[") and " failed (" in normalized_line:
            add_unique(test_failures, normalized_line)

if test_failures:
    for failure in test_failures:
        add_unique(errors, failure)

payload = {
    "status": status,
    "scheme": scheme_name,
    "destination": destination,
    "tests_count": tests_count,
    "tests_failed": tests_failed,
    "warnings": warnings,
    "errors": errors,
    "test_failures": test_failures,
    "log_path": log_path if keep_artifacts else None,
    "result_bundle_path": result_bundle_path if keep_artifacts else None,
    "queued": int(queued),
    "compiled": int(compiled),
    "tested": int(tested),
    "simulator": simulator or None,
}

Path(parsed_path).write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")

if mode == "json":
    print(json.dumps(payload, ensure_ascii=False))
else:
    print(f"STATUS: {status}")
    print(f"SCHEME: {scheme_name}")
    print(f"DESTINATION: {destination}")
    if tests_count is not None or tests_failed is not None:
        print(f"TESTS: total={tests_count if tests_count is not None else 'unknown'} failed={tests_failed if tests_failed is not None else 'unknown'}")
    if status != "SUCCESS" and not tests_count:
        print("NO TESTS RAN: the build or the test launch failed. See ERRORS below.")
    print()
    if errors:
        print("ERRORS:")
        for error in errors:
            print(error)
        print()
    elif status != "SUCCESS":
        tail = [
            line for line in Path(log_path).read_text(encoding="utf-8", errors="replace").splitlines()
            if line.strip() and " warning: " not in line
        ][-30:]
        print("ERRORS: none parsed. Last lines of the xcodebuild log:")
        for line in tail:
            print(line)
        print()
    if test_failures:
        print("TEST FAILURES:")
        for failure in test_failures:
            print(failure)
        print()
    if warnings:
        print("WARNINGS:")
        for warning in warnings:
            print(warning)
    # The last line, so `| tail -1` keeps it. queued is the time spent waiting
    # for the xcodebuild lock and the simulator lock.
    print()
    summary = f"SUMMARY: {status} queued={queued}s compiled={compiled}s tested={tested}s"
    print(summary + (f' simulator="{simulator}"' if simulator else ""))
PY

exit "$EXIT_CODE"
