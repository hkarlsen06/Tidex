#!/bin/bash
# Wrapper script for validate-localization Swift tool
# Usage: ./validate-localization.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
swift run --package-path "$SCRIPT_DIR" validate-localization "$@"
