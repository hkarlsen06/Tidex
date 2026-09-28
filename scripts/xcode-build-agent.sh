#!/usr/bin/env bash
set -euo pipefail

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
if [[ "$ACTION" != "build" && "$ACTION" != "archive" && "$ACTION" != "exportArchive" ]]; then
  echo "XCODE_BUILD_AGENT_ACTION must be build, archive, or exportArchive" >&2
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
HEARTBEAT_PID=""

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
  echo "[xcode-build-agent] build started; heartbeat every ${HEARTBEAT_INTERVAL}s" >&2

  (
    while kill -0 "$XCODEBUILD_PID" 2>/dev/null; do
      sleep "$HEARTBEAT_INTERVAL"
      kill -0 "$XCODEBUILD_PID" 2>/dev/null || exit 0

      local now elapsed
      now="$(date +%s)"
      elapsed=$((now - start_time))
      echo "[xcode-build-agent] alive: build still running (${elapsed}s elapsed)" >&2
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
xa_acquire_lock
${XA_PREFIX[@]+"${XA_PREFIX[@]}"} xcodebuild ${XA_ARGS[@]+"${XA_ARGS[@]}"} "${XCODEBUILD_ARGS[@]}" >"$LOG_FILE" 2>&1 &
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

python3 - "$MODE" "$STATUS" "$JSON_FILE" "$PARSED_FILE" "$LOG_FILE" "$XCRESULT_OK" <<'PY'
import json
import re
import sys
from pathlib import Path

mode, status, json_path, parsed_path, log_path, xcresult_ok = sys.argv[1:7]
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

if not warnings and not errors:
    text = Path(log_path).read_text(encoding="utf-8", errors="replace")

    for line in text.splitlines():
        if " warning: " in line:
            add_unique(warnings, line)
        elif re.search(r"(^|\s)error:", line):
            add_unique(errors, line)

payload = {
    "status": status,
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
PY

exit "$EXIT_CODE"
