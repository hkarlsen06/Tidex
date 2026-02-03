# Fastlane Setup for Tidex

This directory contains Fastlane configuration for uploading App Store Connect metadata.

## Prerequisites

1. **Ruby** (comes pre-installed on macOS)
2. **Bundler**: `gem install bundler`
3. **Node.js** (for metadata generation)
4. **App Store Connect API Key** (see setup below)

## App Store Connect API Key Setup

1. Go to [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api)
2. Click the **+** button to create a new key
3. Name it (e.g., "Fastlane Metadata") and select **Admin** or **App Manager** role
4. Download the `.p8` file (you can only download it once!)
5. Note the **Key ID** and **Issuer ID** from the page

**Important:** Store the `.p8` file outside the repository (e.g., `~/.appstore/` or a secrets directory). Never commit API keys to git.

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `ASC_KEY_ID` | Yes (for upload) | App Store Connect API Key ID |
| `ASC_ISSUER_ID` | Yes (for upload) | App Store Connect Issuer ID |
| `ASC_KEY_PATH` | Yes (for upload) | Absolute path to the `.p8` API key file |
| `CLAUDE_API_KEY` | No | Anthropic API key for auto-translation |

### When Each Variable Is Needed

- **Metadata upload** (`fastlane ios metadata`): Requires all three `ASC_*` variables
- **Metadata generation** (`npm run generate-metadata`): Only requires `CLAUDE_API_KEY` for translations
- **Source-only generation** (`npm run generate-metadata:source-only`): No env vars required

## Local Development Setup

Set environment variables in your shell before running commands:

```bash
# App Store Connect (required for uploading)
export ASC_KEY_ID="YOUR_KEY_ID"
export ASC_ISSUER_ID="YOUR_ISSUER_ID"
export ASC_KEY_PATH="/absolute/path/to/AuthKey_XXXX.p8"

# Claude API (required for auto-translation, optional otherwise)
# Reuses the same key as ios/Scripts/translate-xcstrings.mjs
export CLAUDE_API_KEY="your-claude-api-key"
```

**Tip:** Add these exports to your `~/.zshrc` or `~/.bashrc` for persistence, or create a local (untracked) shell script:

```bash
# ios/.env.local.sh (DO NOT COMMIT)
export ASC_KEY_ID="..."
export ASC_ISSUER_ID="..."
export ASC_KEY_PATH="..."
```

Then source it: `source ios/.env.local.sh`

The `.p8` file should live outside the repository, for example:
- `~/.appstore/AuthKey_XXXX.p8`
- `/Users/yourname/Secrets/AuthKey_XXXX.p8`

## CI/CD Setup

In CI environments, the `.p8` file must be injected from secrets:

1. **Store the key content** as a base64-encoded secret (e.g., `ASC_API_KEY_BASE64`)
2. **Decode and write to disk** at the start of your workflow:
   ```bash
   echo "$ASC_API_KEY_BASE64" | base64 --decode > /tmp/AuthKey.p8
   export ASC_KEY_PATH="/tmp/AuthKey.p8"
   ```
3. **Set the other variables** as plain secrets:
   - `ASC_KEY_ID`
   - `ASC_ISSUER_ID`
   - `CLAUDE_API_KEY`

4. **Clean up** the key file after the job completes (most CI systems do this automatically for `/tmp`)

## Installation

```bash
cd ios
bundle install
npm install
```

This creates a `Gemfile.lock` which should be committed.

## Available Lanes

### Upload Metadata

Generates localized metadata and uploads to App Store Connect:

```bash
cd ios
bundle exec fastlane ios metadata
```

This lane:
1. Validates required environment variables (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`)
2. Runs the metadata generator script to create localized `.txt` files
3. Uploads metadata via `deliver` (no binary, no screenshots)

### Generate Metadata Only

Generate metadata files without uploading:

```bash
cd ios
npm run generate-metadata
# Or via Fastlane:
bundle exec fastlane ios generate_metadata
```

If `CLAUDE_API_KEY` is not set, only source locales (en, nb) are written; translations are skipped with a warning.

### Force Regenerate All Translations

Re-translate all locales even if files already exist:

```bash
cd ios
npm run generate-metadata:force
```

### Validate Metadata Only

Check metadata files for length limits and required fields:

```bash
cd ios
npm run validate-metadata
# Or via Fastlane:
bundle exec fastlane ios validate_metadata
```

## Metadata Structure

### Source of Truth

Edit the structured JSON file, not individual `.txt` files:

```
ios/Scripts/appstore-metadata-source.json
```

This contains metadata for source locales (English and Norwegian Bokmål).

**Tip:** Use the `/ios-whats-new` slash command to automatically generate release notes from git commits.

### Generated Files

The generator script creates `.txt` files in:

```
ios/fastlane/metadata/
├── en-US/
│   ├── name.txt
│   ├── subtitle.txt
│   ├── description.txt
│   ├── keywords.txt
│   └── release_notes.txt
├── nb-NO/
│   └── ...
└── <other-locales>/
    └── ...
```

### Locale Configuration

Supported locales are read from the Xcode project's `knownRegions` in `Tidex.xcodeproj/project.pbxproj`.
The script maps these to App Store Connect folder names automatically.

## Character Limits

| Field | Max Length |
|-------|------------|
| `name` | 30 |
| `subtitle` | 30 |
| `keywords` | 100 |
| `description` | 4000 |
| `release_notes` | 4000 |

## Translations

The generator script uses `CLAUDE_API_KEY` (the same key used by `translate-xcstrings.mjs`) to automatically translate metadata to all configured locales.

**Behavior without `CLAUDE_API_KEY`:**
- Source locales (en, nb) are written from the JSON source
- Translation to other locales is skipped
- A warning is displayed: "CLAUDE_API_KEY not set - skipping translations"

This allows metadata generation to work even without API access, just without auto-translation.

## Troubleshooting

### "Missing required environment variables"

Ensure all three ASC env vars are set before running `fastlane ios metadata`:
```bash
echo $ASC_KEY_ID $ASC_ISSUER_ID $ASC_KEY_PATH
```

### "API key file not found"

- Check that `ASC_KEY_PATH` is an **absolute path**
- Verify the file exists: `ls -la "$ASC_KEY_PATH"`
- Ensure it's the correct `.p8` file from App Store Connect

### "CLAUDE_API_KEY not set - skipping translations"

This is expected if you only want to generate source locales. Set `CLAUDE_API_KEY` to enable auto-translation.

### Metadata validation errors

Check character limits. The generator validates lengths and will report errors for fields exceeding limits.

### Node script fails

Ensure dependencies are installed:

```bash
cd ios
npm install
```
