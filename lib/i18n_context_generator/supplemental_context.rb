# frozen_string_literal: true

module I18nContextGenerator
  # Immutable, named evidence supplied in addition to translations and source usages.
  ContextSource = Data.define(:kind, :name, :content) do
    def initialize(kind:, name:, content:)
      super(
        kind: kind.to_sym,
        name: name.dup.freeze,
        content: content.dup.freeze
      )
    end
  end

  # Converts configured text files and caller-provided values into context records.
  class SupplementalContext
    class << self
      def load(files:, runtime:)
        validate_files!(files)
        validate_runtime!(runtime)

        file_sources = files.map { |path| load_file(path) }
        runtime_sources = runtime.map do |name, content|
          ContextSource.new(
            kind: :runtime,
            name: scrub_text(name),
            content: scrub_text(content)
          )
        end

        (file_sources + runtime_sources).freeze
      end

      private

      def validate_files!(files)
        return if files.is_a?(Array) && files.all? { |path| path.is_a?(String) && !path.strip.empty? }

        raise Error, 'context_files must be an array of non-empty strings'
      end

      def validate_runtime!(runtime)
        raise Error, 'supplemental_context must be a mapping' unless runtime.is_a?(Hash)

        runtime.each do |name, content|
          raise Error, 'supplemental context name must be a non-empty string' unless
            name.is_a?(String) && !name.strip.empty?
          next if content.is_a?(String) && !content.strip.empty?

          raise Error, "supplemental context value for #{name} must be a non-empty string"
        end
      end

      def load_file(path)
        bytes = File.binread(path)
        raise Error, "context file is not text: #{path}" if bytes.include?("\0")

        content = scrub_text(bytes)
        raise Error, "context file is empty: #{path}" if content.strip.empty?

        ContextSource.new(
          kind: :file,
          name: scrub_text(File.basename(path)),
          content: content
        )
      rescue Error
        raise
      rescue SystemCallError => e
        raise Error, "Unable to read context file #{path}: #{e.message}"
      end

      def scrub_text(value)
        value.dup.force_encoding(Encoding::UTF_8).scrub
      end
    end
  end
end
