#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_file="$repo_root/ios/Tidex.xcodeproj/project.pbxproj"

if grep -q 'XCLocalSwiftPackageReference "../../Chat"' "$project_file" \
  || grep -q 'relativePath = ../../Chat;' "$project_file"; then
  cat >&2 <<'EOF'
Tidex is configured to resolve Exyte Chat from the sibling ../../Chat clone.
Run ./scripts/set-chat-package-source.sh remote before committing portable changes.
EOF
  exit 1
fi

if ! grep -q 'repositoryURL = "https://github.com/TidexHQ/Chat.git";' "$project_file"; then
  cat >&2 <<'EOF'
Tidex is not configured to resolve Exyte Chat from https://github.com/TidexHQ/Chat.git.
Run ./scripts/set-chat-package-source.sh remote before committing portable changes.
EOF
  exit 1
fi

echo "Chat package source is remote."
