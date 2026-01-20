# frozen_string_literal: true

require_relative "lib/txcontext/version"

Gem::Specification.new do |spec|
  spec.name = "txcontext"
  spec.version = Txcontext::VERSION
  spec.authors = ["Apps Infrastructure"]
  spec.email = ["apps-infrastructure@automattic.com"]

  spec.summary = "Extract translation context from source code using AI"
  spec.description = "A CLI tool that analyzes source code to extract contextual information for translation keys, improving translation quality with AI-powered analysis."
  spec.homepage = "https://github.com/Automattic/txcontext"
  spec.license = "GPL-2.0-or-later"
  spec.required_ruby_version = ">= 3.1.0"

  spec.files = Dir["lib/**/*", "exe/*", "LICENSE", "README.md"]
  spec.bindir = "exe"
  spec.executables = ["txcontext"]

  spec.add_dependency "concurrent-ruby", "~> 1.2"
  spec.add_dependency "httpx", "~> 1.0"
  spec.add_dependency "oj", "~> 3.16"
  spec.add_dependency "rexml", "~> 3.2"
  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "tty-progressbar", "~> 0.18"
end
