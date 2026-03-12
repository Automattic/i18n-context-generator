# frozen_string_literal: true

RSpec.describe Txcontext::Writers::SwiftWriter do
  def build_result(key, description)
    Txcontext::ContextExtractor::ExtractionResult.new(
      key: key, text: 'text', description: description
    )
  end

  describe '#update_file' do
    it 'updates NSLocalizedString comment parameter' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Test.swift')
        File.write(path, <<~SWIFT)
          let title = NSLocalizedString("settings.title", comment: "")
        SWIFT

        results = { 'settings.title' => build_result('settings.title', 'Title for settings screen') }
        writer = described_class.new

        writer.update_file(path, results)

        output = File.read(path)
        expect(output).to include('comment: "Context: Title for settings screen"')
      end
    end

    it 'updates String(localized:) comment parameter' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Test.swift')
        File.write(path, <<~SWIFT)
          let title = String(localized: "welcome.title", comment: "old comment")
        SWIFT

        results = { 'welcome.title' => build_result('welcome.title', 'Main welcome heading') }
        writer = described_class.new

        writer.update_file(path, results)

        output = File.read(path)
        expect(output).to include('comment: "Context: Main welcome heading"')
        expect(output).not_to include('old comment')
      end
    end

    it 'updates Text() comment parameter' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Test.swift')
        File.write(path, <<~SWIFT)
          Text("button.save", comment: "")
        SWIFT

        results = { 'button.save' => build_result('button.save', 'Save button in editor') }
        writer = described_class.new

        writer.update_file(path, results)

        output = File.read(path)
        expect(output).to include('comment: "Context: Save button in editor"')
      end
    end

    it 'handles multi-line NSLocalizedString calls' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Test.swift')
        File.write(path, <<~SWIFT)
          let msg = NSLocalizedString(
              "multi.line.key",
              comment: "existing"
          )
        SWIFT

        results = { 'multi.line.key' => build_result('multi.line.key', 'Multi-line call') }
        writer = described_class.new

        writer.update_file(path, results)

        output = File.read(path)
        expect(output).to include('comment: "Context: Multi-line call"')
        expect(output).not_to include('"existing"')
      end
    end

    it 'returns true when file was updated' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Test.swift')
        File.write(path, 'let t = NSLocalizedString("k", comment: "")')

        results = { 'k' => build_result('k', 'Description') }
        writer = described_class.new

        expect(writer.update_file(path, results)).to be true
      end
    end

    it 'returns false when no keys match' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Test.swift')
        File.write(path, 'let t = NSLocalizedString("other.key", comment: "")')

        results = { 'nonexistent' => build_result('nonexistent', 'Description') }
        writer = described_class.new

        expect(writer.update_file(path, results)).to be false
      end
    end

    it 'returns falsey for nonexistent file' do
      writer = described_class.new
      expect(writer.update_file('/nonexistent/Test.swift', {})).to be_falsey
    end

    it 'skips "No usage found" descriptions' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Test.swift')
        original = 'let t = NSLocalizedString("k", comment: "keep this")'
        File.write(path, original)

        results = { 'k' => build_result('k', 'No usage found in source code') }
        writer = described_class.new

        writer.update_file(path, results)

        expect(File.read(path)).to eq(original)
      end
    end

    it 'only modifies existing comment: parameters, does not add new ones' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Test.swift')
        original = 'let t = NSLocalizedString("k")'
        File.write(path, original)

        results = { 'k' => build_result('k', 'Description') }
        writer = described_class.new

        writer.update_file(path, results)

        # No comment: param to update, so file should be unchanged
        expect(File.read(path)).to eq(original)
      end
    end
  end

  describe 'context_mode' do
    it 'replaces entire comment in replace mode' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Test.swift')
        File.write(path, 'let t = NSLocalizedString("k", comment: "Manual note from dev")')

        results = { 'k' => build_result('k', 'LLM description') }
        writer = described_class.new(context_mode: 'replace')

        writer.update_file(path, results)

        output = File.read(path)
        expect(output).to include('comment: "Context: LLM description"')
        expect(output).not_to include('Manual note from dev')
      end
    end

    it 'appends context to existing non-context comment in append mode' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Test.swift')
        File.write(path, 'let t = NSLocalizedString("k", comment: "Manual note")')

        results = { 'k' => build_result('k', 'LLM description') }
        writer = described_class.new(context_mode: 'append')

        writer.update_file(path, results)

        output = File.read(path)
        expect(output).to include('Manual note')
        expect(output).to include('Context: LLM description')
      end
    end

    it 'updates existing context in append mode (idempotent)' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Test.swift')
        File.write(path, 'let t = NSLocalizedString("k", comment: "Manual note Context: Old desc")')

        results = { 'k' => build_result('k', 'New desc') }
        writer = described_class.new(context_mode: 'append')

        writer.update_file(path, results)

        output = File.read(path)
        expect(output).to include('Manual note')
        expect(output).to include('Context: New desc')
        expect(output).not_to include('Old desc')
      end
    end
  end

  describe 'context_prefix' do
    it 'uses custom prefix' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Test.swift')
        File.write(path, 'let t = NSLocalizedString("k", comment: "")')

        results = { 'k' => build_result('k', 'Button label') }
        writer = described_class.new(context_prefix: 'Note: ')

        writer.update_file(path, results)

        output = File.read(path)
        expect(output).to include('comment: "Note: Button label"')
      end
    end

    it 'works with empty prefix' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Test.swift')
        File.write(path, 'let t = NSLocalizedString("k", comment: "")')

        results = { 'k' => build_result('k', 'Button label') }
        writer = described_class.new(context_prefix: '')

        writer.update_file(path, results)

        output = File.read(path)
        expect(output).to include('comment: "Button label"')
      end
    end
  end

  describe 'string escaping' do
    it 'escapes quotes in descriptions' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Test.swift')
        File.write(path, 'let t = NSLocalizedString("k", comment: "")')

        results = { 'k' => build_result('k', 'Button saying "OK"') }
        writer = described_class.new

        writer.update_file(path, results)

        output = File.read(path)
        expect(output).to include('\\"OK\\"')
        # File should still be valid (no unescaped quotes breaking the string)
        expect(output.scan('comment:').size).to eq(1)
      end
    end

    it 'escapes newlines in descriptions' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Test.swift')
        File.write(path, 'let t = NSLocalizedString("k", comment: "")')

        results = { 'k' => build_result('k', "Line one\nLine two") }
        writer = described_class.new

        writer.update_file(path, results)

        output = File.read(path)
        # Newlines should be escaped to \n in the Swift string
        expect(output).to include('Line one\\nLine two')
        # Should be on a single line
        expect(output.lines.grep(/comment:/).size).to eq(1)
      end
    end
  end

  describe 'regex escaping of keys' do
    it 'handles keys with dots' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Test.swift')
        File.write(path, <<~SWIFT)
          let a = NSLocalizedString("com.app.title", comment: "")
          let b = NSLocalizedString("comXappXtitle", comment: "keep")
        SWIFT

        results = { 'com.app.title' => build_result('com.app.title', 'App title') }
        writer = described_class.new

        writer.update_file(path, results)

        output = File.read(path)
        expect(output).to include('comment: "Context: App title"')
        # The other key should not be affected (dot should not match any char)
        expect(output).to include('comment: "keep"')
      end
    end
  end

  describe 'idempotency' do
    it 'produces the same output when run twice in replace mode' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Test.swift')
        File.write(path, 'let t = NSLocalizedString("k", comment: "")')

        results = { 'k' => build_result('k', 'Description') }
        writer = described_class.new(context_mode: 'replace')

        writer.update_file(path, results)
        first = File.read(path)

        writer.update_file(path, results)
        second = File.read(path)

        expect(second).to eq(first)
      end
    end
  end
end
