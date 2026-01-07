#!/bin/bash

# Script to properly set the APPLE_PRIVATE_KEY secret for Supabase Edge Functions
#
# Usage:
#   ./scripts/set-apple-private-key.sh path/to/AuthKey_XXXXXXXX.p8
#
# The script will:
# 1. Read the .p8 file
# 2. Convert newlines to \n escape sequences (required for Supabase secrets)
# 3. Set the secret using supabase secrets set

if [ -z "$1" ]; then
    echo "Error: Please provide the path to your Apple .p8 private key file"
    echo ""
    echo "Usage: ./scripts/set-apple-private-key.sh path/to/AuthKey_XXXXXXXX.p8"
    echo ""
    echo "You can download the .p8 file from App Store Connect:"
    echo "  Users and Access → Integrations → In-App Purchase → Keys"
    exit 1
fi

P8_FILE="$1"

if [ ! -f "$P8_FILE" ]; then
    echo "Error: File not found: $P8_FILE"
    exit 1
fi

# Read the file and verify it's a valid PEM key
if ! head -1 "$P8_FILE" | grep -q "BEGIN PRIVATE KEY"; then
    echo "Error: File doesn't appear to be a valid .p8 private key"
    echo "Expected file to start with: -----BEGIN PRIVATE KEY-----"
    exit 1
fi

echo "Reading private key from: $P8_FILE"

# Read the key and escape newlines for the environment variable
# The key needs literal \n characters (not actual newlines) for Supabase secrets
KEY_ESCAPED=$(cat "$P8_FILE" | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')

echo "Key length (with escaped newlines): ${#KEY_ESCAPED} characters"
echo ""
echo "Setting APPLE_PRIVATE_KEY secret..."
echo ""

# Set the secret
supabase secrets set "APPLE_PRIVATE_KEY=$KEY_ESCAPED"

echo ""
echo "Done! The secret has been set."
echo ""
echo "To verify, check the Edge Function logs after making an IAP request."
echo "You should see: [apple-verify] APPLE_PRIVATE_KEY length: <some number > 0>"
