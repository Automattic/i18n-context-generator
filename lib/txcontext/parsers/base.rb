# frozen_string_literal: true

module Txcontext
  module Parsers
    # Represents a single translation entry
    TranslationEntry = Data.define(:key, :text, :source_file, :metadata) do
      def initialize(key:, text:, source_file:, metadata: {})
        super
      end
    end

    # Base class for translation file parsers
    class Base
      def self.for(path)
        basename = File.basename(path).downcase
        ext = File.extname(path).downcase

        case ext
        when ".json"
          JsonParser.new
        when ".yml", ".yaml"
          YamlParser.new
        when ".strings"
          StringsParser.new
        when ".xml"
          # Check if it's an Android strings.xml
          if basename == "strings.xml" || path.include?("/res/values")
            AndroidXmlParser.new
          else
            raise Error, "Unsupported XML format: #{path} (only Android strings.xml is supported)"
          end
        else
          raise Error, "Unsupported translation file format: #{path}"
        end
      end

      def parse(path)
        raise NotImplementedError, "Subclasses must implement #parse"
      end

      protected

      # Flatten nested hashes: {"a" => {"b" => "c"}} -> {"a.b" => "c"}
      def flatten_keys(hash, prefix = nil)
        hash.each_with_object({}) do |(key, value), result|
          full_key = [prefix, key].compact.join(".")

          case value
          when Hash
            result.merge!(flatten_keys(value, full_key))
          when Array
            # Handle arrays (e.g., pluralization)
            result[full_key] = value.join(" | ")
          else
            result[full_key] = value
          end
        end
      end
    end
  end
end
