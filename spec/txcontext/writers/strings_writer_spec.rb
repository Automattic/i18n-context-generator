# frozen_string_literal: true

RSpec.describe Txcontext::Writers::StringsWriter do
  def build_result(key, description, source_file: nil, error: nil)
    Txcontext::ContextExtractor::ExtractionResult.new(
      key: key,
      text: 'text',
      description: description,
      source_file: source_file,
      error: error
    )
  end

  def parsed_comments(path)
    DotStrings.parse_file(path, strict: false).items.to_h { |item| [item.key, item.comment] }
  end

  describe '#write' do
    it 'replaces comments for matching keys and preserves unrelated items' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Localizable.strings')
        File.write(path, <<~STRINGS)
          /* Old note */
          "settings.title" = "Settings";

          /* Keep me */
          "other.key" = "Other";
        STRINGS

        described_class.new.write([build_result('settings.title', 'Settings screen title')], path)

        comments = parsed_comments(path)

        expect(comments['settings.title']).to eq('Context: Settings screen title')
        expect(comments['other.key']).to eq('Keep me')
      end
    end

    it 'appends context to an existing manual comment in append mode' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Localizable.strings')
        File.write(path, <<~STRINGS)
          /* Manual note */
          "settings.title" = "Settings";
        STRINGS

        described_class.new(context_mode: 'append').write(
          [build_result('settings.title', 'Settings screen title')],
          path
        )

        expect(parsed_comments(path)['settings.title']).to eq("Manual note\nContext: Settings screen title")
      end
    end

    it 'updates an existing context line in append mode without duplicating it' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Localizable.strings')
        File.write(path, <<~STRINGS)
          /* Manual note
          Context: Old description */
          "settings.title" = "Settings";
        STRINGS

        writer = described_class.new(context_mode: 'append')
        results = [build_result('settings.title', 'New description')]

        writer.write(results, path)
        first_output = File.read(path)
        writer.write(results, path)
        second_output = File.read(path)

        expect(parsed_comments(path)['settings.title']).to eq("Manual note\nContext: New description")
        expect(second_output.scan('Context:').size).to eq(1)
        expect(second_output).to eq(first_output)
      end
    end

    it 'skips placeholder descriptions and leaves comments unchanged' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Localizable.strings')
        File.write(path, <<~STRINGS)
          /* Manual note */
          "settings.title" = "Settings";
        STRINGS

        described_class.new.write([build_result('settings.title', 'No usage found in source code')], path)

        expect(parsed_comments(path)['settings.title']).to eq('Manual note')
      end
    end

    it 'returns nil for missing files' do
      expect(described_class.new.write([], '/nonexistent/Localizable.strings')).to be_nil
    end

    it 'skips errored results and leaves comments unchanged' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Localizable.strings')
        File.write(path, <<~STRINGS)
          /* Manual note */
          "settings.title" = "Settings";
        STRINGS

        described_class.new.write([build_result('settings.title', 'API error', error: 'timeout')], path)

        expect(parsed_comments(path)['settings.title']).to eq('Manual note')
      end
    end

    it 'scopes duplicate keys by source file' do
      Dir.mktmpdir do |dir|
        english_path = File.join(dir, 'en.strings')
        spanish_path = File.join(dir, 'es.strings')
        File.write(english_path, '"greeting" = "Hello";')
        File.write(spanish_path, '"greeting" = "Hola";')

        results = [
          build_result('greeting', 'English context', source_file: english_path),
          build_result('greeting', 'Spanish context', source_file: spanish_path)
        ]

        writer = described_class.new
        writer.write(results, english_path)
        writer.write(results, spanish_path)

        expect(parsed_comments(english_path)['greeting']).to eq('Context: English context')
        expect(parsed_comments(spanish_path)['greeting']).to eq('Context: Spanish context')
      end
    end
  end
end
