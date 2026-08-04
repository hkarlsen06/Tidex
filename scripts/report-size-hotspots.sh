#!/usr/bin/env bash
set -euo pipefail

threshold="${1:-1000}"
limit="${SIZE_HOTSPOT_LIMIT:-40}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_file="$(mktemp "${TMPDIR:-/tmp}/tidex-size-hotspots.XXXXXX")"

cleanup() {
  rm -f "$tmp_file"
}
trap cleanup EXIT

if ! [[ "$threshold" =~ ^[0-9]+$ ]]; then
  echo "Usage: ./scripts/report-size-hotspots.sh [line-threshold]" >&2
  exit 2
fi

cd "$repo_root"

list_files() {
  if command -v rg >/dev/null 2>&1; then
    rg --files ios supabase/functions marketing \
      -g '*.swift' \
      -g '*.ts' \
      -g '*.tsx'
  else
    find ios supabase/functions marketing -type f \
      \( -name '*.swift' -o -name '*.ts' -o -name '*.tsx' \)
  fi
}

while IFS= read -r file; do
  lines="$(wc -l <"$file" | tr -d ' ')"
  if [ "$lines" -ge "$threshold" ]; then
    printf "%7d %s\n" "$lines" "$file" >>"$tmp_file"
  fi
done < <(list_files)

if [ ! -s "$tmp_file" ]; then
  echo "No Swift/TypeScript files at or above ${threshold} lines."
  exit 0
fi

count="$(wc -l <"$tmp_file" | tr -d ' ')"
echo "Swift/TypeScript files at or above ${threshold} lines (${count} total):"
sort -nr "$tmp_file" | head -n "$limit"

if [ "$count" -gt "$limit" ]; then
  echo "... and $((count - limit)) more. Set SIZE_HOTSPOT_LIMIT to show more."
fi
