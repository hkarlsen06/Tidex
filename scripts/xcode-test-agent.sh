#!/usr/bin/env bash
set -euo pipefail

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
RESULT_BUNDLE="${TMPDIR:-/tmp}/tidex-test-$(date +%s)-$$.xcresult"
LOG_FILE="$(mktemp "${TMPDIR:-/tmp}/tidex-test-log.XXXXXX")"
JSON_FILE="$(mktemp "${TMPDIR:-/tmp}/tidex-test-json.XXXXXX")"
PARSED_FILE="$(mktemp "${TMPDIR:-/tmp}/tidex-test-parsed.XXXXXX")"
XCODEBUILD_PID=""
HEARTBEAT_PID=""
KEEP_ARTIFACTS="${XCODE_TEST_AGENT_KEEP_ARTIFACTS:-0}"

if ! [[ "$HEARTBEAT_INTERVAL" =~ ^[0-9]+$ ]]; then
  HEARTBEAT_INTERVAL="$DEFAULT_HEARTBEAT_INTERVAL"
elif [ "$HEARTBEAT_INTERVAL" -lt "$MIN_HEARTBEAT_INTERVAL" ]; then
  HEARTBEAT_INTERVAL="$MIN_HEARTBEAT_INTERVAL"
fi

cleanup() {
  xa_stop_xcodebuild "${XCODEBUILD_PID:-}"
  xa_release_lock
  if [ -n "${HEARTBEAT_PID:-}" ]; then
    kill "$HEARTBEAT_PID" 2>/dev/null || true
    wait "$HEARTBEAT_PID" 2>/dev/null || true
  fi
  if [ "$KEEP_ARTIFACTS" = "1" ]; then
    return
  fi
  rm -f "$LOG_FILE" "$JSON_FILE" "$PARSED_FILE"
  rm -rf "$RESULT_BUNDLE"
}
trap cleanup EXIT
# shellcheck source=lib/xcode-agent-throttle.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/xcode-agent-throttle.sh"
xa_install_signal_traps

start_heartbeat() {
  local start_time
  start_time="$(date +%s)"
  echo "[xcode-test-agent] tests started; heartbeat every ${HEARTBEAT_INTERVAL}s" >&2

  (
    while kill -0 "$XCODEBUILD_PID" 2>/dev/null; do
      sleep "$HEARTBEAT_INTERVAL"
      kill -0 "$XCODEBUILD_PID" 2>/dev/null || exit 0

      local now elapsed
      now="$(date +%s)"
      elapsed=$((now - start_time))
      echo "[xcode-test-agent] alive: tests still running (${elapsed}s elapsed)" >&2
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

resolve_destination() {
  if [ -n "${XCODE_TEST_AGENT_DESTINATION:-}" ]; then
    printf '%s\n' "$XCODE_TEST_AGENT_DESTINATION"
    return
  fi

  python3 - <<'PY'
import re
import subprocess
import sys

preferred_name = "iPhone 18 Pro"
preferred_runtime_fragment = "iOS 27"

try:
    output = subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available"],
        text=True,
    )
except Exception as exc:
    print(f"failed to list simulators: {exc}", file=sys.stderr)
    sys.exit(1)

runtime = None
booted = None
preferred = None
fallback = None

for raw_line in output.splitlines():
    stripped = raw_line.strip()

    if stripped.startswith("-- ") and stripped.endswith(" --"):
        runtime = stripped[3:-3]
        continue

    if runtime is None or not runtime.startswith("iOS "):
        continue

    match = re.match(
        r"^(?P<name>.+) \((?P<udid>[0-9A-F-]{36})\) \((?P<state>Booted|Shutdown)\)$",
        stripped,
    )
    if not match:
        continue

    name = match.group("name")
    destination = f"platform=iOS Simulator,id={match.group('udid')}"

    if match.group("state") == "Booted" and booted is None:
        booted = destination

    if name == preferred_name and preferred_runtime_fragment in runtime and preferred is None:
        preferred = destination

    if fallback is None and name.startswith("iPhone "):
        fallback = destination

for candidate in (booted, preferred, fallback):
    if candidate:
      print(candidate)
      sys.exit(0)

print("failed to resolve an available iOS Simulator destination", file=sys.stderr)
sys.exit(1)
PY
}

DESTINATION="$(resolve_destination)"

set +e
XCODEBUILD_ARGS=(
  -quiet
  -resultBundlePath "$RESULT_BUNDLE"
  -project "$PROJECT_PATH"
  -scheme "$SCHEME_NAME"
  -destination "$DESTINATION"
  test
)

if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
  XCODEBUILD_ARGS+=("${EXTRA_ARGS[@]}")
fi

xa_configure test ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
xa_acquire_lock
${XA_PREFIX[@]+"${XA_PREFIX[@]}"} xcodebuild ${XA_ARGS[@]+"${XA_ARGS[@]}"} \
  "${XCODEBUILD_ARGS[@]}" >"$LOG_FILE" 2>&1 &
XCODEBUILD_PID=$!
start_heartbeat
wait "$XCODEBUILD_PID"
EXIT_CODE=$?
stop_heartbeat
xa_release_lock
set -e

STATUS="SUCCESS"
if [ "$EXIT_CODE" -ne 0 ]; then
  STATUS="FAILURE"
fi

XCRESULT_OK=0
if [ -d "$RESULT_BUNDLE" ]; then
  set +e
  xcrun xcresulttool get --legacy --format json --path "$RESULT_BUNDLE" >"$JSON_FILE" 2>/dev/null
  XCRESULT_EXIT=$?
  set -e
  if [ "$XCRESULT_EXIT" -eq 0 ] && [ -s "$JSON_FILE" ]; then
    XCRESULT_OK=1
  fi
fi

python3 - "$MODE" "$STATUS" "$JSON_FILE" "$PARSED_FILE" "$LOG_FILE" "$XCRESULT_OK" \
  "$DESTINATION" "$SCHEME_NAME" "$RESULT_BUNDLE" "$KEEP_ARTIFACTS" <<'PY'
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
) = sys.argv[1:11]
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

    def walk(node):
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
                if summary_type == "TestFailureIssueSummary" or test_case_name:
                    add_unique(test_failures, line)
                    add_unique(errors, line)
                elif "warning" in issue_type:
                    add_unique(warnings, line)
                elif "error" in issue_type:
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

            for value in node.values():
                walk(value)

        elif isinstance(node, list):
            for item in node:
                walk(item)

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

    for line in text.splitlines():
        normalized_line = line.strip()
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
        print()
    if errors:
        print("ERRORS:")
        for error in errors:
            print(error)
PY

exit "$EXIT_CODE"
