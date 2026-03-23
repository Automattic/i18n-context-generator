# i18n-context-generator

`i18n-context-generator` generates translator-facing context for your existing localization keys. It reads translation files, finds where each key is used in app code, and asks an LLM to explain the string's UI role in plain language.

You can export the results as CSV or JSON, write them back into `.strings` or `strings.xml`, or update Swift `comment:` arguments directly.

It is designed for mobile codebases. Each run must target either iOS or Android, not both.

## What It Does

- Parses `.strings`, `strings.xml`, `.json`, and `.yml` or `.yaml` translation files
- Searches Swift, Objective-C, Kotlin, Java, and Android XML for matching usages
- Uses Anthropic or OpenAI models to infer UI context
- Supports diff-based runs, key filters, and key ranges for incremental work
- Redacts likely secrets, URLs, and emails from prompts by default
- Optionally caches results to avoid repeating identical LLM work

## Installation

```bash
bundle install
chmod +x exe/i18n-context-generator
```

## Quick Start

Preview what would be processed:

```bash
bundle exec exe/i18n-context-generator extract \
  -t ios/MyApp/Resources/Localizable.strings \
  -s ios/MyApp \
  --dry-run
```

For a real run, set a provider API key:

```bash
export ANTHROPIC_API_KEY=your-api-key
# or
export OPENAI_API_KEY=your-api-key
```

Generate context and save it to CSV:

```bash
bundle exec exe/i18n-context-generator extract \
  -t ios/MyApp/Resources/Localizable.strings \
  -s ios/MyApp \
  -o translation-context.csv
```

Do the same for Android:

```bash
bundle exec exe/i18n-context-generator extract \
  -t android/app/src/main/res/values/strings.xml \
  -s android/app/src/main \
  -o translation-context.csv
```

Write generated context back into translation files:

```bash
bundle exec exe/i18n-context-generator extract \
  -t ios/MyApp/Resources/Localizable.strings \
  -s ios/MyApp \
  --write-back
```

Write generated context back into Swift `comment:` arguments:

```bash
bundle exec exe/i18n-context-generator extract \
  -t ios/MyApp/Resources/Localizable.strings \
  -s ios/MyApp \
  --write-back-to-code
```

Use `--output`, `--write-back`, or `--write-back-to-code` depending on where you want results to go. If you have both iOS and Android code in the same repository, run the tool separately for each platform.

## Configuration

Create a starter config:

```bash
bundle exec exe/i18n-context-generator init
bundle exec exe/i18n-context-generator extract --config .i18n-context-generator.yml
```

Example `.i18n-context-generator.yml`:

```yaml
translations:
  - path: ios/MyApp/Resources/Localizable.strings

source:
  paths:
    - ios/MyApp
  ignore:
    - "**/Pods/**"
    - "**/build/**"
    - "**/*Tests*"

llm:
  provider: anthropic
  model: claude-sonnet-4-6

processing:
  concurrency: 5
  context_lines: 15
  max_matches_per_key: 3

output:
  format: csv
  path: translation-context.csv
  write_back: false
  write_back_to_code: false
  context_prefix: "Context: "
  context_mode: replace

swift:
  functions:
    - NSLocalizedString
    - "String(localized:"
    - "Text("

privacy:
  include_file_paths: false
  include_translation_comments: true
  redact_prompts: true
```

Use a separate config for Android instead of mixing iOS and Android paths in the same run.

## CLI Reference

### Inputs and Output

- `-t`, `--translations FILES`: translation files to process, comma-separated
- `-s`, `--source DIRS`: source files or directories to search, comma-separated
- `-c`, `--config PATH`: load options from `.i18n-context-generator.yml`
- `-o`, `--output PATH`: write results to a file
- `-f`, `--format csv|json`: output format, default `csv`

### LLM Settings

- `-p`, `--provider anthropic|openai`: LLM provider, default `anthropic`
- `-m`, `--model MODEL`: explicit model override
- `--concurrency N`: parallel request count, default `5`

### Filtering and Incremental Runs

- `-k`, `--keys PATTERNS`: wildcard key filter such as `settings.*`
- `--diff-base REF`: process only keys changed since a Git ref
- `--start-key KEY`: start at a specific key, inclusive
- `--end-key KEY`: stop at a specific key, inclusive
- `--dry-run`: preview matching keys without calling the LLM

### Write-Back and Prompt Controls

- `--write-back`: update `.strings` or `strings.xml`
- `--write-back-to-code`: update Swift `comment:` arguments
- `--context-prefix TEXT`: prefix generated comments, default `Context: `
- `--context-mode replace|append`: replace existing comments or append to them
- `--cache`: enable on-disk caching
- `--include-file-paths`: include full source paths in prompts
- `--include-translation-comments`: include existing translation comments in prompts, default `true`
- `--redact-prompts`: redact likely secrets and PII before prompts are sent, default `true`

Run `bundle exec exe/i18n-context-generator help extract` for the full command reference.

## Supported Inputs

### Translation Files

| Format | Notes |
|--------|-------|
| `.strings` | Apple strings files |
| `strings.xml` | Android string resources, including plurals and arrays |
| `.json` | Nested keys are flattened |
| `.yml`, `.yaml` | Nested keys are flattened |

### Source Search

| Platform | Files searched | Typical patterns |
|----------|----------------|------------------|
| iOS | `.swift`, `.m`, `.mm`, `.h` | `NSLocalizedString`, `String(localized:)`, `LocalizedStringKey`, `Text`, `.localized` |
| Android | `.kt`, `.java`, `.xml` | `R.string.*`, `getString(...)`, `stringResource(...)`, `@string/...`, plurals, arrays |

## Output

CSV example:

```csv
key,text,description,ui_element,tone,max_length,locations,error
settings.title,Settings,Navigation bar title for the main settings screen,navigation,neutral,15,ios/SettingsViewController.swift:17,
common.save,Save,Primary action button in forms and edit screens,button,neutral,10,ios/ProfileViewController.swift:31,
error.network,Unable to connect,Error message shown when network requests fail,alert,apologetic,,ios/ProfileViewController.swift:94,
```

With `--write-back`, generated context is written back into translation files:

**Before**

```text
/* Settings screen title */
"settings.title" = "Settings";
```

**After**

```text
/* Context: Navigation bar title for the main settings screen */
"settings.title" = "Settings";
```

With `--write-back-to-code`, Swift `comment:` arguments are updated:

**Before**

```swift
let title = NSLocalizedString("settings.title", comment: "Settings screen title")
```

**After**

```swift
let title = NSLocalizedString("settings.title", comment: "Context: Navigation bar title for the main settings screen")
```

Use `--context-mode append` to preserve existing manual comments, or `--context-prefix ""` to omit the default prefix.

## How It Works

1. Parse translation keys from the input files.
2. Find matching usages in the selected source paths.
3. Send the most relevant matches, plus optional existing comments, to the LLM.
4. Save the generated context to a file or write it back into source files.

## CI Integration

Use `--diff-base` to process only keys changed in a branch or pull request:

```bash
bundle exec exe/i18n-context-generator extract \
  -t ios/Resources/Localizable.strings \
  -s ios \
  --diff-base origin/main \
  --write-back-to-code \
  --context-prefix ""
```

Example GitHub Actions step:

```yaml
- name: Add translation context
  run: |
    bundle exec exe/i18n-context-generator extract \
      -t ios/Resources/Localizable.strings \
      -s ios \
      --diff-base origin/main \
      --write-back-to-code
    git diff --quiet || git commit -am "Add translation context"
```

## Caching

Caching is disabled by default. Enable it with `--cache`.

Cached results are stored in `.i18n-context-generator-cache/`. The cache is refreshed when the translation text or the prompt-shaping inputs change.

## Releasing

1. Add changelog entries under the appropriate subsection in `## Trunk` in `CHANGELOG.md`.
2. Run `bundle exec rake new_release`. It suggests a version based on the changelog, creates a `release/<version>` branch, updates `version.rb`, `Gemfile.lock`, and `CHANGELOG.md`, then commits, pushes, and opens a PR into `trunk`.
3. Merge the release PR on GitHub.
4. Create a GitHub Release targeting `trunk` with the version as the tag. CI publishes the gem to RubyGems.

## License

Licensed under [MPL-2.0](LICENSE).
