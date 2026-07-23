# i18n-context-generator

`i18n-context-generator` generates translator-facing context for your existing localization keys. It reads translation files, finds where each key is used in app code, and asks an LLM to explain the string's UI role in plain language.

You can export the results as CSV or JSON, write them back into `.strings`, `.xcstrings`, or `strings.xml`, or update Swift `comment:` arguments directly.

It is designed for mobile codebases. Each run must target either iOS or Android, not both.

## What It Does

- Parses `.strings`, `.xcstrings`, `strings.xml`, `.json`, and `.yml` or `.yaml` translation files
- Searches Swift, Objective-C, Kotlin, Java, and Android XML for matching usages
- Uses Anthropic, OpenAI, or an explicitly configured OpenAI-compatible endpoint to infer UI context
- Supports diff-based runs, key filters, and key ranges for incremental work
- Separates validation, planning, patch preview, and mutation into explicit workflow stages
- Applies best-effort redaction of likely secrets, URLs, and emails by default
- Optionally caches results to avoid repeating identical LLM work

## Installation

```bash
bundle install
chmod +x exe/i18n-context-generator
```

## Quick Start

Plan what would be processed without calling an LLM:

```bash
bundle exec exe/i18n-context-generator plan \
  -t ios/MyApp/Resources/Localizable.strings \
  -s ios/MyApp
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

Use `--output`, `--stdout`, `--write-back`, or `--write-back-to-code` depending on where you want results to go. `extract` uses the configured `workflow.stage`, which defaults to `apply`; the named workflow commands always select their corresponding stage explicitly. If you have both iOS and Android code in the same repository, run the tool separately for each platform.

## Configuration

Create a starter config:

```bash
bundle exec exe/i18n-context-generator init
bundle exec exe/i18n-context-generator extract --config .i18n-context-generator.yml
```

Example `.i18n-context-generator.yml`:

```yaml
schema_version: 1

translations:
  - path: ios/MyApp/Resources/Localizable.strings

source:
  paths:
    - ios/MyApp
  # Optional additions to the built-in dependency, build, and test ignores
  ignore:
    - "**/*.generated.*"

llm:
  provider: anthropic
  # Optional; each provider has its own default model.
  # model: claude-sonnet-4-6
  # openai_compatible requires an explicit model and endpoint.
  # endpoint: http://127.0.0.1:11434/v1/responses

processing:
  concurrency: 5
  context_lines: 15
  max_matches_per_key: 3
  max_prompt_chars: 50000

cache:
  enabled: false
  directory: .i18n-context-generator-cache

workflow:
  stage: apply

output:
  format: csv
  path: translation-context.csv
  stdout: false
  write_back: false
  write_back_to_code: false
  context_prefix: "Context: "
  context_mode: replace

swift:
  # These syntaxes are used by extraction and Swift comment write-back.
  # Custom entries extend the built-in defaults shown below.
  functions:
    - NSLocalizedString
    - "String(localized:"
    - "Text("

privacy:
  include_file_paths: false
  include_translation_comments: true
  # Best-effort only; source snippets are still sent to the remote provider.
  redact_prompts: true
```

Use a separate config for Android instead of mixing iOS and Android paths in the same run.
Client `source.ignore` entries extend the built-in ignore list; they do not replace it.
Configured `swift.functions` extend the built-in defaults and are used consistently for usage search, source-first discovery, and `--write-back-to-code`. A custom function may be written as either `MyLocalizedString` or `MyLocalizedString(`; its first string argument, with or without a label such as `key:`, is treated as the translation key.
Unversioned configuration files use schema version 1 compatibility mode: unknown options produce warnings and remain ignored as they were before versioning. New files should declare `schema_version: 1`; explicit versioning enables strict unknown-option validation, and future versions fail clearly. Run `i18n-context-generator config validate [PATH]` to validate a file or add `--print-config` to an extraction command to inspect the fully resolved, secret-free configuration.

## CLI Reference

### Inputs and Output

- `-t`, `--translation FILE`: translation file to process; repeat for multiple files
- `-s`, `--source PATH`: source file or directory to search; repeat for multiple paths
- `-c`, `--config PATH`: load options from `.i18n-context-generator.yml`
- `-o`, `--output PATH`: write results to a file
- `--stdout`: write structured CSV or JSON to standard output
- `-f`, `--format csv|json`: output format, default `csv`
- `--print-config`: print the resolved configuration and exit

### LLM Settings

- `-p`, `--provider anthropic|openai|openai_compatible`: LLM provider, default `anthropic`
- `-m`, `--model MODEL`: explicit model override
- `--endpoint URL`: explicit Responses API endpoint for `openai_compatible`
- `--concurrency N`: parallel request count, default `5`
- `--max-prompt-chars N`: hard character limit per LLM prompt, default `50000`

### Filtering and Incremental Runs

- `-k`, `--key PATTERN`: wildcard key filter such as `settings.*`; repeat for multiple patterns
- `--diff-base REF`: process only keys changed since a Git ref
- `--diff-head REF`: compare `--diff-base` to this ref, default `HEAD`
- `--start-key KEY`: start at a specific key, inclusive
- `--end-key KEY`: stop at a specific key, inclusive
- `--dry-run`: preview matching keys without calling the LLM

### Write-Back and Prompt Controls

- `--write-back`: update `.strings`, `.xcstrings`, or `strings.xml`
- `--write-back-to-code`: update Swift `comment:` arguments
- `--context-prefix TEXT`: prefix generated comments, default `Context: `
- `--context-mode replace|append`: replace existing comments or append to them
- `--cache`: enable on-disk caching
- `--cache-dir PATH`: cache directory, default `.i18n-context-generator-cache`
- `--include-file-paths`: include full source paths in prompts
- `--include-translation-comments`: include existing translation comments in prompts, default `true`
- `--redact-prompts`: best-effort redact likely secrets and PII before prompts are sent, default `true`

Run `bundle exec exe/i18n-context-generator help extract` for the full command reference.

The legacy `--translations` and `--keys` flags still accept comma-separated lists with a deprecation warning. Repeatable singular flags always preserve literal commas in paths and key patterns.

### Workflow stages

- `check`: validate configuration and confirm source usage without calling the LLM
- `plan`: list selected keys and destinations without calling the LLM
- `preview-diff`: generate context and print the exact write-back patch to stdout
  without changing translation, source, or structured-output files; diagnostics
  go to stderr
- `apply`: generate context and write to the configured destinations
- `extract`: compatibility entry point that uses `workflow.stage` from configuration, defaulting to `apply`

`--dry-run` remains available as a compatibility shortcut for non-mutating key selection. Use `preview-diff` when you need to inspect generated write-back content rather than only the selected keys.

### Prompt privacy and size

Remote-provider runs send translation text and selected source snippets off the machine. By default, full paths are reduced to basenames and the tool applies pattern-based redaction to keys, text, comments, paths, scopes, matched lines, and surrounding context. This is a best-effort safeguard, not a guarantee that all private or identifying data will be detected. Review the source paths and translation comments you configure before using a remote provider.

`processing.max_prompt_chars` bounds each user prompt. When evidence exceeds the limit, surrounding code and optional metadata are truncated deterministically, with the translation key, text, and at least one usage receiving priority. Provider output is validated against the application contract before it can reach an output writer.

For a local or third-party Responses API, select `openai_compatible` and configure both `llm.model` and `llm.endpoint`. Plain HTTP is accepted only for loopback endpoints; remote endpoints must use HTTPS. Authentication is isolated to `OPENAI_COMPATIBLE_API_KEY`, so this provider never implicitly forwards `OPENAI_API_KEY` to a custom host.

```yaml
llm:
  provider: openai_compatible
  model: local-model-name
  endpoint: http://127.0.0.1:11434/v1/responses
```

### Cache behavior

Caching is opt-in and stores successful results only; provider, resolved model, custom endpoint, prompt controls, source context, and source-discovery locations are part of each cache identity. Writes use private temporary files and atomic replacement so concurrent workers cannot leave partial JSON behind.

The default directory is `.i18n-context-generator-cache`. Add that directory—or your custom `cache.directory`—to the client repository's `.gitignore`; cached LLM output should not be committed. The generated starter configuration keeps caching disabled by default.

## Supported Inputs

### Translation Files

| Format | Notes |
|--------|-------|
| `.strings` | Apple strings files |
| `.xcstrings` | Apple string catalogs; reads the source language, comments, and plural variations |
| `strings.xml` | Android string resources, including plurals and arrays |
| `.json` | Read-only hydration source; nested keys are flattened |
| `.yml`, `.yaml` | Read-only hydration source; nested keys are flattened and locale roots must be configured explicitly |

For Rails-style YAML files with a locale root, name that root in the translation entry. Without `locale:`, the top-level key is retained as part of every translation key; locale-shaped application namespaces are never guessed or removed.

```yaml
translations:
  - path: config/locales/en.yml
    locale: en
```

### Source Search

| Platform | Files searched | Typical patterns |
|----------|----------------|------------------|
| iOS | `.swift`, `.m`, `.mm`, `.h` | `NSLocalizedString`, `String(localized:)`, `LocalizedStringResource`, `LocalizedStringKey`, `Text`, `.localized` |
| Android | `.kt`, `.java`, `.xml` | `R.string.*`, `getString(...)`, `stringResource(...)`, `@string/...`, plurals, arrays |

## Output

CSV example:

```csv
key,text,description,ui_element,tone,max_length,confidence,ambiguity_reason,locations,status,cache_hit,request_count,input_tokens,output_tokens,retries,error
settings.title,Settings,Navigation bar title for the main settings screen,navigation,neutral,15,high,,ios/SettingsViewController.swift:17,success,false,1,834,61,0,
```

JSON and CSV output schema version 1 includes source-file and translation-key
identity, complete and changed-only evidence locations, side-aware translation
diff locations, confidence, ambiguity, token counts, retries, and request count.
This keeps duplicate keys from different translation files distinguishable. The
run summary reports aggregate requests, cache hits, tokens, retries, and an
estimated list-price cost when the selected model has known pricing. Cost is
informational and does not account for provider-specific discounts or billing
adjustments.

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

`--diff-base` compares against `HEAD` by default. Pass `--diff-head` when a CI system prepares explicit refs:

```bash
bundle exec exe/i18n-context-generator extract \
  -t ios/Resources/Localizable.strings \
  -s ios \
  --diff-base danger_base \
  --diff-head danger_head \
  --output translation-context.json
```

Programmatic callers can use the same range and may pass enum-style options as strings or symbols:

```ruby
config = I18nContextGenerator::Config.new(
  translations: ['ios/Resources/Localizable.strings'],
  source_paths: ['ios'],
  discovery_mode: :translations,
  provider: :anthropic,
  diff_base: 'danger_base',
  diff_head: 'danger_head'
)

extractor = I18nContextGenerator::ContextExtractor.new(
  config,
  quiet: true,
  progress: false
)
extractor.run

extractor.results.each do |result|
  result.status                         # :success, :no_usage, or :error
  result.actionable?                    # Safe to present to a user
  result.locations                      # Every source location used as extraction evidence
  result.changed_locations              # Source evidence changed inside the configured range
  result.changed_location_groups        # Changed source lines grouped by localization occurrence
  result.translation_key                # Owning translation resource (including Android collections)
  # ChangedLocation objects with file, line, side (:left/:right), and an
  # optional right-side fallback_line for review suggestions.
  result.changed_translation_locations
end
```

An invalid ref or failed `git diff` raises `I18nContextGenerator::Error`; it is never reported as an unchanged range.
Programmatic callers may also inject `log_output:`, `structured_output:`, and
`patch_output:` streams instead of using the process-wide standard streams.

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
