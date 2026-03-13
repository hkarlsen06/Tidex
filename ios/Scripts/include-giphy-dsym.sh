#!/bin/sh

set -eu

if [ "${PLATFORM_NAME:-}" != "iphoneos" ]; then
  echo "Skipping Giphy dSYM copy for PLATFORM_NAME=${PLATFORM_NAME:-unknown}"
  exit 0
fi

SOURCE_DSYM_ZIP="${SRCROOT}/Vendor/Giphy/ios_devices_GiphyUISDK.framework.dSYM.zip"
DESTINATION_DSYM="${DWARF_DSYM_FOLDER_PATH}/GiphyUISDK.framework.dSYM"
TEMP_DIR="$(mktemp -d "${TMPDIR%/}/giphy-dsym.XXXXXX")"

trap 'rm -rf "$TEMP_DIR"' EXIT

if [ ! -f "$SOURCE_DSYM_ZIP" ]; then
  echo "Missing vendored Giphy dSYM zip at: $SOURCE_DSYM_ZIP"
  exit 1
fi

if [ -z "${DWARF_DSYM_FOLDER_PATH:-}" ]; then
  echo "DWARF_DSYM_FOLDER_PATH is not set"
  exit 1
fi

ditto -x -k "$SOURCE_DSYM_ZIP" "$TEMP_DIR"

SOURCE_DSYM="${TEMP_DIR}/ios_devices_GiphyUISDK.framework.dSYM"

if [ ! -d "$SOURCE_DSYM" ]; then
  echo "Expanded Giphy dSYM was not found at: $SOURCE_DSYM"
  exit 1
fi

mkdir -p "$DWARF_DSYM_FOLDER_PATH"
rm -rf "$DESTINATION_DSYM"
cp -R "$SOURCE_DSYM" "$DESTINATION_DSYM"

echo "Copied Giphy dSYM to $DESTINATION_DSYM"
