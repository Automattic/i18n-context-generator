# txcontext

Ruby CLI gem that extracts contextual information from mobile app source code to improve translation quality. Analyzes how localized strings are used in iOS/Android codebases and generates descriptions for translators.

## Architecture

```
lib/txcontext/
├── cli.rb                 # Thor-based CLI entry point
├── config.rb              # YAML config file loading (.txcontext.yml)
├── context_extractor.rb   # Main orchestrator - ties everything together
├── searcher.rb            # Finds string usages in source code
├── cache.rb               # File-based caching for LLM results
├── git_diff.rb            # Git diff parsing for --diff-base
├── llm/
│   ├── client.rb          # LLM provider interface
│   └── anthropic.rb       # Claude API implementation
├── parsers/               # Read translation files
│   ├── strings_parser.rb  # iOS .strings files
│   ├── android_xml_parser.rb
│   ├── json_parser.rb
│   └── yaml_parser.rb
└── writers/               # Write results
    ├── csv_writer.rb      # Default output format
    ├── json_writer.rb
    ├── strings_writer.rb  # Write-back to .strings
    ├── android_xml_writer.rb
    └── swift_writer.rb    # Write-back to Swift comment: params
```

## Key Components

### Searcher (`lib/txcontext/searcher.rb`)

Finds where translation keys are used in source code. Critical for providing context to the LLM.

**Platform detection**: Auto-detects iOS vs Android based on file extensions in source paths.

**iOS patterns** (single-line):
- `NSLocalizedString("key", ...)` - Swift and Objective-C (supports `@"key"` syntax)
- `String(localized: "key", ...)` - modern Swift
- `LocalizedStringKey("key")` - SwiftUI
- `Text("key")` - SwiftUI
- `"key".localized` - common extension pattern

**Supported file types**: `.swift`, `.m`, `.mm`, `.h`

**Multi-line support**: iOS codebases often use multi-line `NSLocalizedString` calls:
```swift
cell.accessibilityLabel = NSLocalizedString(
    "Add a tracking",
    comment: "..."
)
```

The searcher handles this by:
1. First checking single-line patterns
2. For iOS files, also running `find_multiline_ios_matches` which looks for quoted strings containing the key, then checks if preceding lines (up to 5) contain a function opener like `NSLocalizedString(`

**Android patterns**:
- `R.string.key_name`
- `@string/key_name` (XML)
- `getString(R.string.key)` / `stringResource(R.string.key)`
- Static import patterns: `string.key_name`

### Context Extractor (`lib/txcontext/context_extractor.rb`)

Main orchestrator that:
1. Loads translation keys from parser
2. Applies filters (--keys, --diff-base, --start-key/--end-key)
3. For each key, searches source code via Searcher
4. Sends context to LLM for analysis
5. Writes results via writer

### LLM Client (`lib/txcontext/llm/anthropic.rb`)

Calls Claude API with structured output. The prompt asks Claude to analyze:
- What UI element the string appears in
- The tone/voice
- Any length constraints
- A description for translators

## Running

```bash
# Basic usage (no CSV output, no caching by default)
bundle exec exe/txcontext extract -t Localizable.strings -s ./Sources

# With CSV output
bundle exec exe/txcontext extract -t Localizable.strings -s ./Sources -o context.csv

# Dry run (no API calls)
bundle exec exe/txcontext extract -t Localizable.strings -s ./Sources --dry-run

# Specific keys only
bundle exec exe/txcontext extract -t Localizable.strings -s ./Sources --keys "Add a tracking,Save"

# Enable caching (disabled by default)
bundle exec exe/txcontext extract -t Localizable.strings -s ./Sources --cache
```

## Ruby API

For programmatic usage (e.g., fastlane integration), use the classes directly instead of shelling out to the CLI:

```ruby
require 'txcontext'

config = Txcontext::Config.new(
  translations: ['/path/to/Localizable.strings'],
  source_paths: ['/path/to/Sources'],
  diff_base: 'origin/main',      # Only process changed keys
  write_back: true,              # Write context back to translation file
  context_prefix: '',            # No prefix (default is "Context: ")
  context_mode: 'replace'        # Replace existing comments
  # output_path: 'out.csv'       # Optional: CSV only written if specified
  # no_cache: false              # Optional: enable caching (disabled by default)
)

extractor = Txcontext::ContextExtractor.new(config)
extractor.run
```

### Config Options

Key `Txcontext::Config` parameters:
- `translations`: Array of translation file paths
- `source_paths`: Array of source code directories to search
- `diff_base`: Git ref to compare against (only process changed keys)
- `write_back`: Write context as comments to translation files
- `write_back_to_code`: Write context to Swift `comment:` parameters
- `context_prefix`: Prefix for context comments (empty string for none)
- `context_mode`: `"replace"` or `"append"` existing comments
- `output_path`: CSV output path (default: `nil`, no CSV written unless specified)
- `no_cache`: Disable caching (default: `true`, caching disabled by default)
- `dry_run`: Preview without LLM calls
- `key_filter`: Comma-separated patterns to filter keys

## Testing

### RSpec Test Suite

Run the full test suite:

```bash
bundle exec rspec
```

Run specific spec files:

```bash
bundle exec rspec spec/txcontext/searcher_spec.rb
bundle exec rspec spec/txcontext/parsers/
```

### Test Structure

```
spec/
├── spec_helper.rb
└── txcontext/
    ├── searcher_spec.rb              # Pattern matching, multi-line, false positives
    ├── config_spec.rb                # Config loading, CLI parsing, defaults
    └── parsers/
        ├── strings_parser_spec.rb    # iOS .strings parsing
        └── android_xml_parser_spec.rb # Android XML parsing, plurals, arrays
```

### Test Fixtures

Located in `test-fixtures/` with realistic iOS and Android source files:

```
test-fixtures/
├── ios/
│   ├── Localizable.strings           # Translation keys
│   ├── SettingsViewController.swift  # NSLocalizedString patterns
│   ├── ProfileViewController.swift   # Various iOS patterns
│   ├── QuickStartView.swift          # SwiftUI Text/String(localized:)
│   ├── MultilineExamples.swift       # Multi-line NSLocalizedString
│   ├── SwiftUIExamples.swift         # LocalizedStringKey, Text patterns
│   ├── LocalizedExtension.swift      # .localized extension
│   ├── FalsePositives.swift          # Patterns that should NOT match
│   └── LegacyStrings.m/.h            # Objective-C patterns
└── android/
    ├── res/values/strings.xml        # Translation keys
    ├── res/layout/activity_main.xml  # @string/key XML patterns
    └── app/src/main/java/com/example/myapp/
        ├── SettingsActivity.kt       # getString() patterns
        ├── ProfileActivity.kt        # Various Android patterns
        ├── PostAdapter.kt            # R.string patterns
        ├── ComposeScreen.kt          # stringResource() Jetpack Compose
        └── StaticImportExample.kt    # Static import patterns
```

### Quick Manual Testing

For ad-hoc searcher verification without running full specs:

```ruby
$LOAD_PATH.unshift "lib"
require "txcontext/searcher"

searcher = Txcontext::Searcher.new(
  source_paths: ["test-fixtures/ios"],
  ignore_patterns: [],
  context_lines: 10,
  platform: :ios
)

matches = searcher.search("Some Key")
matches.each { |m| puts "#{m.file}:#{m.line} - #{m.match_line}" }
```

## Common Issues

**"no usage found in source code"**: The searcher couldn't find where the key is used. Common causes:
- Multi-line function calls (fixed with `find_multiline_ios_matches`)
- Custom localization wrappers not in the pattern list
- Key only exists in translation file, not actually used in code

**False positives**: The searcher has `FALSE_POSITIVE_PATTERNS` to filter out things like string comparisons (`== "key"`), `.equals()` calls, etc.
