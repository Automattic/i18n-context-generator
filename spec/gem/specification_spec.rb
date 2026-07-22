# frozen_string_literal: true

require 'rubygems/package'

RSpec.describe Gem::Specification do
  subject(:specification) do
    described_class.load(File.expand_path('../../i18n-context-generator.gemspec', __dir__))
  end

  it 'packages csv as a runtime dependency for Ruby versions where it is not a default gem' do
    packaged_specification = Dir.mktmpdir do |dir|
      gem_path = File.join(dir, 'i18n-context-generator.gem')
      Gem::Package.build(specification, true, false, gem_path)
      Gem::Package.new(gem_path).spec
    end
    csv_dependency = packaged_specification.runtime_dependencies.find { |dependency| dependency.name == 'csv' }

    expect(csv_dependency).not_to be_nil
    expect(csv_dependency.requirement).to be_satisfied_by(Gem::Version.new(CSV::VERSION))
  end

  it 'bounds every development dependency' do
    unbounded = specification.development_dependencies.select do |dependency|
      dependency.requirement == Gem::Requirement.default
    end

    expect(unbounded).to be_empty
  end
end
