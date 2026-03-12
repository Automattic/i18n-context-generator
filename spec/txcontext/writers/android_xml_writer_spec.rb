# frozen_string_literal: true

RSpec.describe Txcontext::Writers::AndroidXmlWriter do
  def build_result(key, description)
    Txcontext::ContextExtractor::ExtractionResult.new(
      key: key, text: 'text', description: description
    )
  end

  describe '#write' do
    it 'adds context comments above single-line <string> elements' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'strings.xml')
        File.write(path, <<~XML)
          <resources>
              <string name="app_name">My App</string>
              <string name="greeting">Hello</string>
          </resources>
        XML

        results = [
          build_result('app_name', 'The app display name'),
          build_result('greeting', 'Welcome greeting on home screen')
        ]

        writer = described_class.new
        writer.write(results, path)

        output = File.read(path)

        expect(output).to include("<!-- Context: The app display name -->\n    <string name=\"app_name\">")
        expect(output).to include("<!-- Context: Welcome greeting on home screen -->\n    <string name=\"greeting\">")
      end
    end

    it 'adds comments above multi-line <string> elements' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'strings.xml')
        File.write(path, <<~XML)
          <resources>
              <string name="long_text">
                  This is a very long string
                  that spans multiple lines
              </string>
          </resources>
        XML

        results = [build_result('long_text', 'A multi-line description')]

        writer = described_class.new
        writer.write(results, path)

        output = File.read(path)

        expect(output).to include("<!-- Context: A multi-line description -->\n    <string name=\"long_text\">")
      end
    end

    it 'preserves original formatting' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'strings.xml')
        original = <<~XML
          <?xml version="1.0" encoding="utf-8"?>
          <resources>
              <string name="only_key">Value</string>
          </resources>
        XML
        File.write(path, original)

        results = [build_result('only_key', 'The description')]
        writer = described_class.new
        writer.write(results, path)

        output = File.read(path)

        # XML declaration and resources tags should be preserved
        expect(output).to include('<?xml version="1.0" encoding="utf-8"?>')
        expect(output).to include('<resources>')
        expect(output).to include('</resources>')
      end
    end

    it 'does not add comments on <plurals> or <string-array> elements' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'strings.xml')
        File.write(path, <<~XML)
          <resources>
              <plurals name="item_count">
                  <item quantity="one">%d item</item>
                  <item quantity="other">%d items</item>
              </plurals>
              <string-array name="colors">
                  <item>Red</item>
                  <item>Blue</item>
              </string-array>
          </resources>
        XML

        results = [
          build_result('item_count:one', 'Singular item count'),
          build_result('colors[0]', 'First color')
        ]

        writer = described_class.new
        writer.write(results, path)

        output = File.read(path)

        # No comment should appear above <plurals> or <string-array>
        expect(output).not_to include('<!-- Context: Singular item count -->')
        expect(output).not_to include('<!-- Context: First color -->')
      end
    end

    it 'skips "No usage found" descriptions' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'strings.xml')
        File.write(path, <<~XML)
          <resources>
              <string name="unused_key">Unused</string>
          </resources>
        XML

        results = [build_result('unused_key', 'No usage found in source code')]

        writer = described_class.new
        writer.write(results, path)

        output = File.read(path)

        expect(output).not_to include('<!-- Context:')
      end
    end
  end

  describe 'section header preservation' do
    it 'preserves non-txcontext comments (section headers)' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'strings.xml')
        File.write(path, <<~XML)
          <resources>
              <!-- Settings Screen -->
              <string name="settings_title">Settings</string>
          </resources>
        XML

        results = [build_result('settings_title', 'Title for settings screen')]

        writer = described_class.new
        writer.write(results, path)

        output = File.read(path)

        # Section header should be preserved
        expect(output).to include('<!-- Settings Screen -->')
        # Context comment should also be added
        expect(output).to include('<!-- Context: Title for settings screen -->')
      end
    end

    it 'updates existing txcontext comments in place' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'strings.xml')
        File.write(path, <<~XML)
          <resources>
              <!-- Context: Old description -->
              <string name="key">Value</string>
          </resources>
        XML

        results = [build_result('key', 'New description')]

        writer = described_class.new
        writer.write(results, path)

        output = File.read(path)

        expect(output).to include('<!-- Context: New description -->')
        expect(output).not_to include('Old description')
        # Should not create duplicate comments
        expect(output.scan('<!--').size).to eq(1)
      end
    end
  end

  describe 'idempotency' do
    it 'produces the same output when run twice' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'strings.xml')
        File.write(path, <<~XML)
          <resources>
              <string name="key">Value</string>
          </resources>
        XML

        results = [build_result('key', 'Description')]
        writer = described_class.new

        writer.write(results, path)
        first_output = File.read(path)

        writer.write(results, path)
        second_output = File.read(path)

        expect(second_output).to eq(first_output)
      end
    end

    it 'is idempotent with empty prefix' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'strings.xml')
        File.write(path, <<~XML)
          <resources>
              <string name="key">Value</string>
          </resources>
        XML

        results = [build_result('key', 'Description')]
        writer = described_class.new(context_prefix: '')

        writer.write(results, path)
        first_output = File.read(path)

        writer.write(results, path)
        second_output = File.read(path)

        expect(second_output).to eq(first_output)
      end
    end
  end

  describe 'context_mode' do
    it 'replaces existing comments in replace mode' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'strings.xml')
        File.write(path, <<~XML)
          <resources>
              <!-- Context: Old description -->
              <string name="key">Value</string>
          </resources>
        XML

        results = [build_result('key', 'New description')]
        writer = described_class.new(context_mode: 'replace')
        writer.write(results, path)

        output = File.read(path)
        expect(output).to include('Context: New description')
        expect(output).not_to include('Old description')
      end
    end

    it 'appends to non-txcontext comments in append mode' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'strings.xml')
        File.write(path, <<~XML)
          <resources>
              <!-- Translator note: formal -->
              <string name="key">Value</string>
          </resources>
        XML

        results = [build_result('key', 'Button label')]
        writer = described_class.new(context_mode: 'append')
        writer.write(results, path)

        output = File.read(path)

        # Non-txcontext comment is not ours, so we insert a new comment
        expect(output).to include('<!-- Translator note: formal -->')
        expect(output).to include('<!-- Context: Button label -->')
      end
    end
  end

  describe 'comment escaping' do
    it 'escapes double dashes in descriptions' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'strings.xml')
        File.write(path, <<~XML)
          <resources>
              <string name="key">Value</string>
          </resources>
        XML

        results = [build_result('key', 'Use -- for separator')]
        writer = described_class.new
        writer.write(results, path)

        output = File.read(path)

        # Double dash is invalid in XML comments, should be escaped
        expect(output).not_to include('<!-- Context: Use -- for')
        expect(output).to include('- -')
      end
    end
  end

  describe 'build_results_lookup' do
    it 'maps plural keys to base name' do
      writer = described_class.new

      results = [
        build_result('count:one', 'Singular count'),
        build_result('count:other', 'Plural count')
      ]

      lookup = writer.send(:build_results_lookup, results)

      # Base name maps to first result (sorted by key)
      expect(lookup['count']).not_to be_nil
      expect(lookup['count'].key).to eq('count:one')
    end

    it 'maps array keys to base name' do
      writer = described_class.new

      results = [
        build_result('days[0]', 'First day'),
        build_result('days[1]', 'Second day')
      ]

      lookup = writer.send(:build_results_lookup, results)

      expect(lookup['days']).not_to be_nil
      expect(lookup['days'].key).to eq('days[0]')
    end

    it 'is deterministic regardless of input order' do
      writer = described_class.new

      results_a = [
        build_result('count:other', 'Plural'),
        build_result('count:one', 'Singular')
      ]

      results_b = [
        build_result('count:one', 'Singular'),
        build_result('count:other', 'Plural')
      ]

      lookup_a = writer.send(:build_results_lookup, results_a)
      lookup_b = writer.send(:build_results_lookup, results_b)

      expect(lookup_a['count'].key).to eq(lookup_b['count'].key)
    end
  end
end
