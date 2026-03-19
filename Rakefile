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
