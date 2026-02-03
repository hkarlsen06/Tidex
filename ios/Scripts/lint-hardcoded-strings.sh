#!/bin/bash
# Wrapper script for lint-hardcoded-strings Swift tool
# Usage: ./lint-hardcoded-strings.sh [--strict] [--path <path>]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
swift run --package-path "$SCRIPT_DIR" lint-hardcoded-strings "$@"
