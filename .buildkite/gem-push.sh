#!/bin/bash -eu

GEM_NAME="i18n-context-generator"
CREDENTIALS_FILE="$(mktemp "${TMPDIR:-/tmp}/i18n-context-generator-gem-credentials.XXXXXX")"

cleanup() {
  rm -f "$CREDENTIALS_FILE"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

: "${RUBYGEMS_API_KEY:?RUBYGEMS_API_KEY must be set}"

echo "--- :hammer: Build Gemspec"
gem build "$GEM_NAME.gemspec" -o "$GEM_NAME.gem"

echo "--- :sleuth_or_spy: Validate Gem Install"
gem install --user-install "$GEM_NAME.gem"

echo "--- :rubygems: Gem Push"
printf ':rubygems_api_key: %s\n' "$RUBYGEMS_API_KEY" >"$CREDENTIALS_FILE"
chmod 600 "$CREDENTIALS_FILE"
unset RUBYGEMS_API_KEY
gem push --config-file "$CREDENTIALS_FILE" "$GEM_NAME.gem"
