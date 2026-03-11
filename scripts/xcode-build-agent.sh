#!/usr/bin/env bash
set -euo pipefail

MODE="text"
if [ "${1:-}" = "--json" ]; then
  MODE="json"
fi

RESULT_BUNDLE="$(mktemp -d "${TMPDIR:-/tmp}/tidex-build-XXXXXX.xcresult")"
LOG_FILE="$(mktemp "${TMPDIR:-/tmp}/tidex-build-log.XXXXXX")"
JSON_FILE="$(mktemp "${TMPDIR:-/tmp}/tidex-build-json.XXXXXX")"
PARSED_FILE="$(mktemp "${TMPDIR:-/tmp}/tidex-build-parsed.XXXXXX")"

cleanup() {
  rm -f "$LOG_FILE" "$JSON_FILE" "$PARSED_FILE"
  rm -rf "$RESULT_BUNDLE"
}
trap cleanup EXIT

set +e
xcodebuild \
  -quiet \
  -resultBundlePath "$RESULT_BUNDLE" \
  -project ios/Tidex.xcodeproj \
  -scheme App \
  -destination 'generic/platform=iOS Simulator' \
  build >"$LOG_FILE" 2>&1
EXIT_CODE=$?
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
        elif " error: " in line:
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
