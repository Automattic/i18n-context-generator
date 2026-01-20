# frozen_string_literal: true

module Txcontext
  module LLM
    # Result from LLM context generation
    ContextResult = Data.define(:description, :ui_element, :tone, :max_length, :error) do
      def initialize(description:, ui_element: nil, tone: nil, max_length: nil, error: nil)
        super
      end
    end

    # Base class for LLM clients
    class Client
      def self.for(provider)
        case provider.to_s.downcase
        when "anthropic"
          Anthropic.new
        when "openai"
          raise Error, "OpenAI provider not yet implemented"
        when "ollama"
          raise Error, "Ollama provider not yet implemented"
        else
          raise Error, "Unknown LLM provider: #{provider}"
        end
      end

      def generate_context(key:, text:, matches:, model: nil)
        raise NotImplementedError, "Subclasses must implement #generate_context"
      end

      protected

      def build_prompt(key:, text:, matches:)
        platform = detect_platform(matches)

        <<~PROMPT
          You are analyzing a localized string from a #{platform} mobile app to help translators understand its context.

          ## Translation Key
          `#{key}`

          ## Original Text
          "#{text}"

          ## Code Usage
          #{format_matches(matches)}

          ## Task
          Analyze how this string is used in the mobile app code and provide context for translators.

          Focus on:
          1. **Where it appears**: What screen or view displays this text?
          2. **UI element type**: Is it a button label, navigation title, alert message, placeholder, etc.?
          3. **User action**: What action triggers this text or what happens when the user interacts with it?
          4. **Constraints**: Are there any length constraints (e.g., button width, navigation bar)?

          Write a concise context description (1-2 sentences) that helps a translator understand:
          - The purpose of this text in the app
          - The UI context where it appears
          - Any important considerations for translation

          Respond with ONLY a JSON object (no markdown, no explanation):
          {
            "description": "Concise context for translators (1-2 sentences)",
            "ui_element": "button|label|title|alert|toast|placeholder|navigation|menu|tab|error|confirmation|other",
            "tone": "formal|casual|urgent|friendly|technical|neutral",
            "max_length": null or number if there's an apparent character limit
          }
        PROMPT
      end

      def detect_platform(matches)
        return "mobile" if matches.empty?

        extensions = matches.map { |m| File.extname(m.file).downcase }

        if extensions.any? { |e| [".swift", ".m", ".mm"].include?(e) }
          "iOS"
        elsif extensions.any? { |e| [".kt", ".java"].include?(e) }
          "Android"
        else
          "mobile"
        end
      end

      def format_matches(matches)
        matches.map.with_index do |match, i|
          <<~MATCH
            ### Match #{i + 1}: #{match.file}:#{match.line}
            ```
            #{match.context}
            ```
          MATCH
        end.join("\n")
      end

      def parse_response(text)
        return ContextResult.new(description: "Failed to parse response", error: "Empty response") if text.nil? || text.empty?

        # Try to extract JSON from the response
        json_text = extract_json(text)
        return ContextResult.new(description: text.strip, error: nil) unless json_text

        data = Oj.load(json_text, symbol_keys: true)

        ContextResult.new(
          description: data[:description] || "No description provided",
          ui_element: data[:ui_element],
          tone: data[:tone],
          max_length: data[:max_length]
        )
      rescue Oj::ParseError => e
        ContextResult.new(description: text.strip, error: "JSON parse error: #{e.message}")
      end

      def extract_json(text)
        # Try to find JSON object in the response
        # Handle both raw JSON and markdown-wrapped JSON
        if text.include?("```")
          # Extract from code block
          match = text.match(/```(?:json)?\s*(\{[^`]+\})\s*```/m)
          return match[1] if match
        end

        # Try to find raw JSON object
        match = text.match(/\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}/m)
        match&.[](0)
      end
    end
  end
end
