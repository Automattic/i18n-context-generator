# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe I18nContextGenerator::Searcher do
  describe '#search when required directly' do
    it 'loads its standard-library and gem dependencies' do
      lib_path = File.expand_path('../../lib', __dir__)
      script = <<~RUBY
        require 'i18n_context_generator/searcher'

        searcher = I18nContextGenerator::Searcher.new(source_paths: [], ignore_patterns: [])
        searcher.search('unused')
      RUBY

      output, status = Open3.capture2e(RbConfig.ruby, '-I', lib_path, '-e', script)

      expect(status).to be_success, output
    end
  end
end
