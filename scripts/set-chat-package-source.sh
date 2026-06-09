#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/set-chat-package-source.sh <local|remote>

  local   Use the sibling ../Chat clone as a local Swift package
  remote  Use the committed TidexHQ/Chat fork from GitHub
EOF
}

mode="${1:-}"

if [[ "$mode" != "local" && "$mode" != "remote" ]]; then
  usage
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_file="$repo_root/ios/Tidex.xcodeproj/project.pbxproj"
local_chat_dir="$repo_root/../Chat"
relative_local_chat_path="../../Chat"

if [[ "$mode" == "local" && ! -d "$local_chat_dir/.git" ]]; then
  echo "Expected local Chat clone at $local_chat_dir" >&2
  exit 1
fi

ruby - "$mode" "$project_file" "$relative_local_chat_path" <<'RUBY'
mode, project_file, relative_local_chat_path = ARGV
contents = File.read(project_file)

remote_package_reference = '11CD7FA32F63CFC700A987E7 /* XCRemoteSwiftPackageReference "Chat" */'
local_package_reference = %(11CD7FA32F63CFC700A987E7 /* XCLocalSwiftPackageReference "#{relative_local_chat_path}" */)
remote_reference = [
  "\t\t11CD7FA32F63CFC700A987E7 /* XCRemoteSwiftPackageReference \"Chat\" */ = {",
  "\t\t\tisa = XCRemoteSwiftPackageReference;",
  "\t\t\trepositoryURL = \"https://github.com/TidexHQ/Chat.git\";",
  "\t\t\trequirement = {",
  "\t\t\t\tkind = revision;",
  "\t\t\t\trevision = ebd451b27813fb2a714bb36c61ccc99e4bbc1dc3;",
  "\t\t\t};",
  "\t\t};",
  "",
].join("\n")
local_reference = [
  %(\t\t11CD7FA32F63CFC700A987E7 /* XCLocalSwiftPackageReference "#{relative_local_chat_path}" */ = {),
  "\t\t\tisa = XCLocalSwiftPackageReference;",
  "\t\t\trelativePath = #{relative_local_chat_path};",
  "\t\t};",
  "",
].join("\n")
remote_dependency = [
  "\t\t11CD7FA42F63CFC700A987E7 /* ExyteChat */ = {",
  "\t\t\tisa = XCSwiftPackageProductDependency;",
  "\t\t\tpackage = 11CD7FA32F63CFC700A987E7 /* XCRemoteSwiftPackageReference \"Chat\" */;",
  "\t\t\tproductName = ExyteChat;",
  "\t\t};",
  "",
].join("\n")
local_dependency = [
  "\t\t11CD7FA42F63CFC700A987E7 /* ExyteChat */ = {",
  "\t\t\tisa = XCSwiftPackageProductDependency;",
  "\t\t\tproductName = ExyteChat;",
  "\t\t};",
  "",
].join("\n")

case mode
when "local"
  current_mode = if contents.include?(local_reference)
    :local
  elsif contents.include?(remote_reference)
    :remote
  else
    :unknown
  end

  if current_mode == :remote
    contents = contents.sub(remote_reference, local_reference)
    contents = contents.sub(remote_dependency, local_dependency)
    contents = contents.sub(remote_package_reference, local_package_reference)
  elsif current_mode == :unknown
    abort("Could not find the Chat package reference in #{project_file}")
  end
when "remote"
  current_mode = if contents.include?(remote_reference)
    :remote
  elsif contents.include?(local_reference)
    :local
  else
    :unknown
  end

  if current_mode == :local
    contents = contents.sub(local_reference, remote_reference)
    contents = contents.sub(local_dependency, remote_dependency)
    contents = contents.sub(local_package_reference, remote_package_reference)
  elsif current_mode == :unknown
    abort("Could not find the Chat package reference in #{project_file}")
  end
else
  abort("Unsupported mode #{mode}")
end

File.write(project_file, contents)
RUBY

(
  cd "$repo_root/ios"
  xcodebuild -resolvePackageDependencies -project Tidex.xcodeproj -scheme App >/dev/null
)

if [[ "$mode" == "local" ]]; then
  echo "Chat now resolves from $local_chat_dir"
else
  echo "Chat now resolves from https://github.com/TidexHQ/Chat.git"
fi
