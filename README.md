# txcontext

A CLI tool that extracts contextual information from mobile app source code to improve translation quality. Uses AI to analyze how localized strings are used in your iOS and Android codebase and generates descriptions to help translators produce better translations.

## Features

- **iOS Support**: Parses `.strings` files and searches Swift/Objective-C code
- **Android Support**: Parses `strings.xml` files and searches Kotlin/Java code
- **AI-Powered Context**: Uses Claude or other LLMs to understand UI context
- **Write-Back**: Optionally writes context comments back to source files
- **Caching**: Avoids re-processing unchanged translations

## Installation

```bash
cd txcontext
bundle install
chmod +x exe/txcontext
```

### Requirements

- Ruby 3.1+
- An Anthropic API key (or other supported LLM provider)

## Quick Start

```bash
# Set your API key
export ANTHROPIC_API_KEY=your-api-key

# iOS app
bundle exec exe/txcontext extract \
  -t ios/MyApp/Resources/Localizable.strings \
  -s ios/MyApp/

# Android app
bundle exec exe/txcontext extract \
  -t android/app/src/main/res/values/strings.xml \
  -s android/app/src/main/java/

# Dry run (preview without calling API)
bundle exec exe/txcontext extract \
  -t Localizable.strings \
  -s . \
  --dry-run

# Write context back to source files
bundle exec exe/txcontext extract \
  -t Localizable.strings \
  -s . \
  --write-back
```

## Usage

### CLI Options

```
-c, --config CONFIG        Path to config file (txcontext.yml)
-t, --translations FILES   Translation file(s), comma-separated
-s, --source DIRS          Source directory(ies) to search, comma-separated
-o, --output PATH          Output file path (default: translation-context.csv)
-f, --format FORMAT        Output format: csv or json (default: csv)
-p, --provider PROVIDER    LLM provider: anthropic (default: anthropic)
-m, --model MODEL          LLM model to use
-k, --keys PATTERNS        Filter keys (comma-separated patterns, supports * wildcard)
    --concurrency N        Number of concurrent requests (default: 5)
    --dry-run              Show what would be processed without calling LLM
    --no-cache             Disable caching
    --write-back           Write context back to source translation files (.strings, strings.xml)
    --write-back-to-code   Write context back to Swift source code comment: parameters
    --diff-base REF        Only process keys changed since this git ref (e.g., main, origin/main)
    --context-prefix TEXT  Prefix for context comments (default: "Context: ", use "" for none)
    --context-mode MODE    How to handle existing comments: replace or append (default: replace)
```

### Using a Config File

```bash
# Create a config file
bundle exec exe/txcontext init

# Run with config
bundle exec exe/txcontext extract --config txcontext.yml
```

Example `txcontext.yml`:

```yaml
# Translation files to process
translations:
  # iOS
  - path: ios/MyApp/Resources/Localizable.strings

  # Android
  - path: android/app/src/main/res/values/strings.xml

# Source code directories to search
source:
  paths:
    - ios/MyApp/
    - android/app/src/main/java/
  ignore:
    - "**/Pods/**"
    - "**/build/**"
    - "**/*Tests*"

# LLM configuration
llm:
  provider: anthropic
  model: claude-sonnet-4-20250514

# Processing options
processing:
  concurrency: 5
  context_lines: 20
  max_matches_per_key: 3

# Output configuration
output:
  format: csv
  path: translation-context.csv
  write_back: false            # Write to .strings / strings.xml
  write_back_to_code: false    # Write to Swift comment: parameters
  context_prefix: "Context: "  # Prefix for comments (use "" for none)
  context_mode: replace        # "replace" existing comments or "append" to them

# Swift-specific configuration
swift:
  functions:
    - NSLocalizedString
    - "String(localized:"
    - "Text("
```

## Supported Formats

### Translation Files

| Format | Extension | Platform |
|--------|-----------|----------|
| Apple Strings | `.strings` | iOS/macOS |
| Android XML | `strings.xml` | Android |
| JSON | `.json` | Cross-platform |
| YAML | `.yml`, `.yaml` | Cross-platform |

### Source Code

| Language | Extensions | Patterns Detected |
|----------|------------|-------------------|
| Swift | `.swift` | `NSLocalizedString("key", comment:)` |
| Objective-C | `.m`, `.mm` | `NSLocalizedString(@"key", ...)` |
| Kotlin | `.kt` | `getString(R.string.key)`, `context.getString(...)` |
| Java | `.java` | `getString(R.string.key)`, `getResources().getString(...)` |

## Output Examples

### CSV Output

```csv
key,text,description,ui_element,tone,max_length,locations,error
settings.title,Settings,Navigation bar title for the main settings screen,navigation,neutral,15,ios/SettingsViewController.swift:17,
common.save,Save,Primary action button in forms and edit screens,button,neutral,10,ios/ProfileViewController.swift:31,
error.network,Unable to connect,Error message shown when network requests fail,alert,apologetic,,ios/ProfileViewController.swift:94,
```

### Write-Back Examples

#### Translation Files (`--write-back`)

**Before** (`Localizable.strings`):
```
/* Settings screen title */
"settings.title" = "Settings";
```

**After**:
```
/* Settings screen title
Context: Navigation bar title for the main settings screen */
"settings.title" = "Settings";
```

#### Swift Source Code (`--write-back-to-code`)

**Before**:
```swift
let title = NSLocalizedString("settings.title", comment: "Settings screen title")
```

**After**:
```swift
let title = NSLocalizedString("settings.title", comment: "Context: Navigation bar title for the main settings screen")
```

#### Without Prefix (`--context-prefix ""`)

If you prefer no prefix, use `--context-prefix ""`:

```swift
// Result with --context-prefix ""
let title = NSLocalizedString("settings.title", comment: "Navigation bar title for the main settings screen")
```

## How It Works

1. **Parse**: Reads translation keys from `.strings` or `strings.xml` files
2. **Search**: Scans source code to find where each key is used
3. **Analyze**: Sends code context to Claude to understand UI usage
4. **Output**: Writes context to CSV/JSON and optionally back to source files

## CI Integration

Use `--diff-base` to process only changed translation keys in a PR, avoiding the need for persistent cache:

```bash
# Process only keys changed since main branch
txcontext extract \
  -t Localizable.strings \
  -s ios/ \
  --diff-base origin/main \
  --write-back-to-code \
  --context-prefix "" \
  --no-cache
```

Example GitHub Actions workflow:

```yaml
- name: Add translation context
  run: |
    txcontext extract \
      -t ios/Resources/Localizable.strings \
      -s ios/ \
      --diff-base origin/main \
      --write-back-to-code \
      --no-cache
    git diff --quiet || git commit -am "Add translation context"
```

## Caching

Results are cached in `.txcontext-cache/` to avoid re-processing unchanged translations. Cache is invalidated when:
- The translation text changes
- You use `--no-cache` flag

## Comparison with Crowdin Context Harvester

| Feature | txcontext | Crowdin Context Harvester |
|---------|-----------|---------------------------|
| Platform focus | Mobile (iOS/Android) | General |
| Vendor lock-in | None | Crowdin |
| Write-back to source | Yes | No (uploads to Crowdin) |
| Language | Ruby | JavaScript |
| LLM providers | Anthropic (more coming) | OpenAI, Gemini, Azure, Anthropic, Mistral |

## License

GPL-2.0-or-later
