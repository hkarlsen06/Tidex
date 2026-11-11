#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "--devices" ]; then
  if command -v ios-agent >/dev/null 2>&1; then
    exec ios-agent devices --json
  fi
  echo "ios-agent is unavailable; use XCODE_TEST_AGENT_DESTINATION for an explicit destination" >&2
  exit 2
fi

MODE="text"
EXTRA_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --json) MODE="json"; shift ;;
    --) shift; EXTRA_ARGS+=("$@"); break ;;
    *) EXTRA_ARGS+=("$1"); shift ;;
  esac
done
ACTION="${XCODE_BUILD_AGENT_ACTION:-build}"
DESTINATION="${XCODE_BUILD_AGENT_DESTINATION:-generic/platform=iOS Simulator}"
# build-for-testing also compiles the test targets.
if [[ "$ACTION" != "build" && "$ACTION" != "build-for-testing" && "$ACTION" != "archive" && "$ACTION" != "exportArchive" ]]; then
  echo "XCODE_BUILD_AGENT_ACTION must be build, build-for-testing, archive, or exportArchive" >&2
  exit 2
fi

DEFAULT_HEARTBEAT_INTERVAL=20
MIN_HEARTBEAT_INTERVAL=15
HEARTBEAT_INTERVAL="${XCODE_BUILD_AGENT_HEARTBEAT_INTERVAL:-$DEFAULT_HEARTBEAT_INTERVAL}"
RESULT_BUNDLE="${TMPDIR:-/tmp}/tidex-build-$(date +%s)-$$.xcresult"
LOG_FILE="$(mktemp "${TMPDIR:-/tmp}/tidex-build-log.XXXXXX")"
JSON_FILE="$(mktemp "${TMPDIR:-/tmp}/tidex-build-json.XXXXXX")"
PARSED_FILE="$(mktemp "${TMPDIR:-/tmp}/tidex-build-parsed.XXXXXX")"
XCODEBUILD_PID=""

if ! [[ "$HEARTBEAT_INTERVAL" =~ ^[0-9]+$ ]]; then
  HEARTBEAT_INTERVAL="$DEFAULT_HEARTBEAT_INTERVAL"
elif [ "$HEARTBEAT_INTERVAL" -lt "$MIN_HEARTBEAT_INTERVAL" ]; then
  HEARTBEAT_INTERVAL="$MIN_HEARTBEAT_INTERVAL"
fi

cleanup() {
  xa_stop_xcodebuild "${XCODEBUILD_PID:-}"
  xa_stop_heartbeat
  rm -f "$LOG_FILE" "$JSON_FILE" "$PARSED_FILE" "${XA_STATUS_FILE:-}"
  rm -rf "$RESULT_BUNDLE"
}
trap cleanup EXIT
# shellcheck source=lib/xcode-agent-throttle.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/xcode-agent-throttle.sh"
xa_install_signal_traps

set +e
if [[ "$ACTION" == "exportArchive" ]]; then
  XCODEBUILD_ARGS=(-quiet -exportArchive)
else
  XCODEBUILD_ARGS=(
    -quiet
    -resultBundlePath "$RESULT_BUNDLE"
    -project ios/Tidex.xcodeproj
    -scheme App
    -destination "$DESTINATION"
    "$ACTION"
  )
fi
if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
  XCODEBUILD_ARGS+=("${EXTRA_ARGS[@]}")
fi
xa_configure "${ACTION:-build}"
QUEUE_START="$(date +%s)"
"${XA_XCODEBUILD[@]}" ${XA_ARGS[@]+"${XA_ARGS[@]}"} "${XCODEBUILD_ARGS[@]}" >"$LOG_FILE" 2>&1 &
XCODEBUILD_PID=$!
xa_start_heartbeat build
wait "$XCODEBUILD_PID"
EXIT_CODE=$?
xa_stop_heartbeat
[ "$EXIT_CODE" -eq 0 ] || xa_controller_messages "$LOG_FILE"
COMPILE_START="$(xa_started "$QUEUE_START")"
QUEUED=$((COMPILE_START - QUEUE_START))
COMPILED=$(($(date +%s) - COMPILE_START))
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
  "$QUEUED" "$COMPILED" <<'PY'
import json
import re
import sys
from pathlib import Path

mode, status, json_path, parsed_path, log_path, xcresult_ok, queued, compiled = sys.argv[1:9]
xcresult_ok = xcresult_ok == "1"

warnings = []
errors = []

def add_unique(target, value):
    value = (value or "").strip()
    if value and value not in target:
        target.append(value)

def unwrap(value):
    if isinstance(value, dict) and "_value" in value:
        return value["_value"]
    return value

def extract_from_xcresult(data):
    def walk(node):
        if isinstance(node, dict):
            issue_type = unwrap(node.get("issueType"))
            message = unwrap(node.get("message")) or ""
            location = ""

            docloc = node.get("documentLocationInCreatingWorkspace")
            if isinstance(docloc, dict):
                location = unwrap(docloc.get("url")) or ""

            if issue_type and message:
                line = f"{location}: {message}" if location else message
                t = str(issue_type).lower()
                if "warning" in t:
                    add_unique(warnings, line)
                elif "error" in t or "testfailure" in t:
                    add_unique(errors, line)

            for v in node.values():
                walk(v)

        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(data)

if xcresult_ok:
    try:
        with open(json_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        extract_from_xcresult(data)
    except Exception:
        pass

# Some failures, such as package resolution, never reach the result bundle, so read the log
# whenever the bundle named no error. Warnings come from the log only when the bundle had none.
if not errors:
    text = Path(log_path).read_text(encoding="utf-8", errors="replace")
    scan_warnings = not warnings

    for line in text.splitlines():
        if " warning: " in line:
            if scan_warnings:
                add_unique(warnings, line)
        elif re.search(r"(^|\s)error:", line):
            add_unique(errors, line)

    if status != "SUCCESS" and not errors:
        # Nothing looks like an error, so show the end of the log instead of nothing.
        errors.extend(line for line in text.splitlines()[-30:] if line.strip())

payload = {
    "status": status,
    "queued": int(queued),
    "compiled": int(compiled),
    "warnings": warnings,
    "errors": errors,
}

Path(parsed_path).write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")

if mode == "json":
    print(json.dumps(payload, ensure_ascii=False))
else:
    print(f"STATUS: {status}")
    print()
    if warnings:
        print("WARNINGS:")
        for w in warnings:
            print(w)
        print()
    if errors:
        print("ERRORS:")
        for e in errors:
            print(e)
    # The last line, so `| tail -1` keeps it. queued is the time spent waiting
    # in the build queue.
    print()
    print(f"SUMMARY: {status} queued={queued}s compiled={compiled}s")
PY

exit "$EXIT_CODE"
