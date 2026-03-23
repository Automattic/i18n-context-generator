# frozen_string_literal: true

require 'rspec/core/rake_task'
require 'rubocop/rake_task'

task default: :all

desc 'Runs all tasks: :specs and :rubocop'
task all: %i[specs rubocop]

desc 'Run Unit Tests'
RSpec::Core::RakeTask.new(:specs)

desc 'Run RuboCop'
RuboCop::RakeTask.new(:rubocop)

VERSION_FILE = File.join('lib', 'i18n_context_generator', 'version.rb')

desc 'Create a new release of the i18n-context-generator gem'
task :new_release do
  require_relative(VERSION_FILE)

  changelog = ChangelogParser.new
  current = I18nContextGenerator::VERSION

  Console.header "Current version: #{current}"
  Console.warning "VERSION (#{current}) does not match CHANGELOG (#{changelog.latest_version})" unless changelog.latest_version == current

  Console.header 'Pending changes:'
  Console.print_indented_lines(changelog.pending_lines)

  new_version = Console.prompt('New version', changelog.guessed_next_version(current: current))

  GitHelper.checkout_release_branch(new_version)

  Console.header 'Updating version...'
  File.write(VERSION_FILE, File.read(VERSION_FILE).gsub(/VERSION = .*/, "VERSION = '#{new_version}'"))
  sh('bundle', 'install', '--quiet')

  Console.header 'Updating CHANGELOG...'
  changelog.write_release(new_version: new_version)

  Console.header 'Committing and pushing...'
  GitHelper.commit_and_push("Bump version to #{new_version}", [VERSION_FILE, 'Gemfile.lock', 'CHANGELOG.md'])

  Console.header 'Opening PR draft...'
  GitHelper.open_pr(new_version, changelog.pending_lines.join)

  Console.info <<~MSG

    ---------------
    >>> WHAT'S NEXT

    Once the PR is merged, publish a GitHub Release for `#{new_version}` targeting `trunk`.
    The git tag will trigger CI to publish the gem to RubyGems.

  MSG
end
