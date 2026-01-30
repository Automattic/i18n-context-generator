# frozen_string_literal: true

require "bundler/setup"
require "txcontext"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Run specs in random order to surface order dependencies
  config.order = :random
  Kernel.srand config.seed
end

# Helper to get the path to test fixtures
module FixtureHelpers
  def fixtures_path
    File.expand_path("../test-fixtures", __dir__)
  end

  def ios_fixtures_path
    File.join(fixtures_path, "ios")
  end

  def android_fixtures_path
    File.join(fixtures_path, "android")
  end

  def ios_source_files
    Dir.glob(File.join(ios_fixtures_path, "*.swift")) +
      Dir.glob(File.join(ios_fixtures_path, "*.m"))
  end

  def android_source_files
    Dir.glob(File.join(android_fixtures_path, "**", "*.kt")) +
      Dir.glob(File.join(android_fixtures_path, "**", "*.xml"))
  end
end

RSpec.configure do |config|
  config.include FixtureHelpers
end
