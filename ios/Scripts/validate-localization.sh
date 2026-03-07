#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
exec swift run --package-path "$script_dir" validate-localization "$@"
