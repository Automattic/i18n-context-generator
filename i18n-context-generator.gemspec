# frozen_string_literal: true

require_relative 'lib/i18n_context_generator/version'

Gem::Specification.new do |spec|
  spec.name = 'i18n-context-generator'
  spec.version = I18nContextGenerator::VERSION
  spec.authors = 'Automattic'
  spec.email = 'mobile@automattic.com'

  spec.summary = 'Extract translation context from source code using AI'
  spec.description = 'A CLI tool that analyzes source code to extract contextual information for translation keys, improving translation quality with AI-powered analysis.'
  spec.homepage = 'https://github.com/Automattic/i18n-context-generator'
  spec.license = 'MPL-2.0'
  spec.required_ruby_version = '>= 3.2.0'

  spec.files = Dir['lib/**/*', 'exe/*', 'LICENSE', 'README.md']
  spec.bindir = 'exe'
  spec.executables = ['i18n-context-generator']

  spec.add_dependency 'concurrent-ruby', '~> 1.2'
  spec.add_dependency 'csv', '~> 3.3'
  spec.add_dependency 'dotstrings', '~> 0.6'
  spec.add_dependency 'oj', '~> 3.16'
  spec.add_dependency 'rexml', '~> 3.2'
  spec.add_dependency 'thor', '~> 1.3'
  spec.add_dependency 'tty-progressbar', '~> 0.18'

  spec.add_development_dependency 'rspec', '~> 3.13'
  spec.add_development_dependency 'rubocop-rake', '~> 0.7'
  spec.add_development_dependency 'rubocop-rspec', '~> 3.9'
end
