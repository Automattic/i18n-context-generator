# i18n-context-generator CHANGELOG

---

## Trunk

### Breaking Changes

_None_

### New Features

_None_

### Bug Fixes

- Preserve Android XML diff content whose leading plus signs resemble a file header.

### Internal Changes

_None_

## 0.5.1

### Bug Fixes

- Send nullable structured-output enums in a provider-compatible schema.
- Index large Unicode Apple string catalogs with consistent byte offsets.

## 0.5.0

### Breaking Changes

_None_

### New Features

- Support explicit base and head refs for diff-backed extraction.
- Expose changed source and translation locations separately from the complete extraction evidence.
- Support Apple string catalogs (`.xcstrings`) and `LocalizedStringResource` usages.
- Add explicit `check`, `plan`, `preview-diff`, and `apply` workflow stages.
- Add versioned structured CSV/JSON output and repeatable singular CLI input flags.
- Report confidence, ambiguity, request counts, cache hits, token usage, retries,
  and estimated model cost.
- Add an explicit, credential-isolated OpenAI-compatible provider for local and
  HTTPS endpoints.
- Add a versioned configuration schema, `config validate`, and `--print-config`.
- Expose side-aware translation diff locations and injectable programmatic I/O.
- Accept multiple free-form context files and named runtime context as redacted,
  prompt-injection-resistant evidence with cache-safe content invalidation.

### Bug Fixes

- Raise actionable errors when Git diff execution fails instead of treating the range as unchanged.
- Normalize symbol values accepted by the programmatic configuration API.
- Scope diff-selected duplicate keys to the translation file that changed.
- Limit changed Android collection entries to the exact plural quantity or array item.
- Track complete multiline iOS localization calls so comment-only changes remain discoverable.
- Expose machine-readable extraction result status instead of requiring consumers to match placeholder text.
- Avoid duplicate no-change messages for translation diff runs.
- Preserve source location occurrence groups so multiline changes produce one integration result per call.
- Preserve Android plural and array parent comments as extraction evidence.
- Map changed Apple string-catalog values and comments back to their owning keys,
  including removals on diverged base branches.
- Canonicalize absolute source-directory diff paths and decode escaped Apple keys.
- Preserve removed-side translation changes and reset Android XML state between
  separate diff hunks.
- Reject unknown options in explicitly versioned configurations and unknown
  translation-entry keys instead of silently ignoring client typos.
- Preserve Apple string-catalog formatting and accept empty placeholder,
  compact, and mixed-layout entries.
- Keep preview patches repository-relative and prevent preview workflows from
  modifying structured-output files.
- Skip no-op `.strings` and Android XML replacements.
- Preserve failed-request telemetry, custom-endpoint cache identity, literal
  commas in repeatable flags, and explicit client overrides.

### Internal Changes

- Cache Android collection member resolution per changed location during diff filtering.
- Centralize localization syntax, path/file policies, resource indexing, result
  serialization, and generated-comment handling.
- Document why AST extraction and provider batching remain evidence-driven
  follow-up work.

## 0.4.0

### New Features

- Add source-first localization discovery. [9c14c4b]

## 0.3.0

### New Features

- First published Gem release.
- Add release workflow via `rake new_release`. [1a4128a]

### Internal Changes

- Improve README and fix CLI entrypoint. [4932692]
- Remove requirements for running the application. [1618d90]
- Fix Rubocop offenses and move rubocop task to linter queue. [6c204d2, afac8f4]

## 0.2.0

### New Features

- Renamed gem from `txcontext` to `i18n-context-generator`. [326620d]
- Setup CI jobs for linting and Gem publishing. [b373fea]

### Bug Fixes

- Tighten iOS wrapper usage matching. [53ce103]
- Exit non-zero on extraction errors. [a592e7e]
- Reduce speculation in context extraction. [bbf3714]

## 0.1.0

### New Features

- Initial gem creation as `txcontext`. [151af68]
- Refactor localization parsing to use dedicated parser libraries. [66a1302]
- Add function to write context back to Swift files. [eeb9983]
- Add `--diff-base` option for CI-friendly PR workflows. [04038b6]
- Add configs to append custom context. [c2712ce]
- Implement string range processing (`--start-key`/`--end-key`). [9dafef4]
- Add OpenAI LLM provider option. [75d1728]
- Redact sensitive data in LLM prompts. [29d2cc8]

### Bug Fixes

- Reimplement searcher with pure Ruby, replacing shell-based approach. [3036330]
- Fix iOS multiline strings search. [8387286]
- Fix Android search patterns. [75c5aa7]
- Fix NSLocalizedString pattern to support Objective-C `@"string"` syntax. [aed79f4]
- Handle escaped quotes in Swift comments. [4bec87c]
- Skip non-translatable Android resources. [d5265b3]
- Fix nested diff-base pathspecs. [e093075]
- Fix config flags, glob matching, and LLM client safety. [62d0f6b]
- Fix extraction and write-back correctness. [3096cb7]
- Harden CSV output against formula injection. [2051ccf]
- Reject mixed-platform extraction runs. [5dd982f]
- Write CSV output only if a path is configured. [00e1130]

### Internal Changes

- Add RSpec test suite and expand test fixtures. [e35e22e]
- Improve tests and coverage. [4688396, df9d006]
- Update license to MPL-2.0. [bda139a]
