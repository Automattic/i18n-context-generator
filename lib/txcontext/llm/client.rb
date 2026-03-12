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

      def generate_context(key:, text:, matches:, model: nil, comment: nil)
        raise NotImplementedError, "Subclasses must implement #generate_context"
      end

      protected

      def build_prompt(key:, text:, matches:, comment: nil)
        platform = detect_platform(matches)

        placeholder_info = detect_placeholders(text)

        <<~PROMPT
          You are analyzing a localized string from a #{platform} mobile app to help translators understand its context.

          ## Translation Key
          `#{key}`

          ## Original Text
          "#{text}"
          #{"\n## Developer Comment\n\"#{comment}\"\n" if comment && !comment.strip.empty?}#{"\n## Format Placeholders\n#{placeholder_info}\n" if placeholder_info}
          ## Code Usage
          #{format_matches(matches)}

          ## Task
          Analyze how this string is used in the mobile app code and provide context for translators.

          **IMPORTANT - Avoid False Positives:**
          - Look for ACTUAL UI USAGE, not coincidental code patterns
          - Ignore method calls that happen to match the key (e.g., `.apply()`, `.close()`, `.clear()` are methods, not UI strings)
          - Ignore boolean/string comparisons (e.g., `if value == "yes"` is not UI usage)
          - Ignore analytics event names or tracking parameters
          - Focus on localization patterns: getString(), NSLocalizedString(), Text(), @string/, R.string., etc.
          - If no clear UI usage is found in the code, base your description on the text itself and common mobile UI patterns

          Focus on:
          1. **Where it appears**: What screen or view displays this text?
          2. **UI element type**: Is it a button label, navigation title, alert message, placeholder, etc.?
          3. **User action**: What action triggers this text or what happens when the user interacts with it?
          4. **Constraints**: Are there any length constraints (e.g., button width, navigation bar)?

          Write a concise context description (1-2 sentences) that helps a translator understand:
          - The purpose of this text in the app
          - The UI context where it appears
          - Any important considerations for translation

          **Quality Guidelines:**
          - Be SPECIFIC about WHERE and HOW the text is used, not just what it means
          - Avoid vague descriptions like "used throughout the app" - identify specific screens/features
          - If the text is a common UI term (Save, Cancel, OK), describe its specific usage context in THIS app
          - Don't mention code implementation details - focus on the user-facing experience

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
          scope_info = match.enclosing_scope ? " (in #{match.enclosing_scope})" : ""
          <<~MATCH
            ### Match #{i + 1}: #{match.file}:#{match.line}#{scope_info}
            ```
            #{match.context}
            ```
          MATCH
        end.join("\n")
      end

      def detect_placeholders(text)
        # iOS: %@, %d, %f, %ld, %lld, %1$@, %2$d, etc.
        # Android: %s, %d, %f, %1$s, %2$d, etc.
        placeholders = text.scan(/%(?:(\d+)\$)?([#0 +'.-]*\d*(?:\.\d+)?(?:l{0,2}|h{0,2})?[diouxXeEfFgGaAcsSpn@])/)
        return nil if placeholders.empty?

        descriptions = []
        # Also gather the raw matches for display
        raw = text.scan(/%(?:\d+\$)?[#0 +'.-]*\d*(?:\.\d+)?(?:l{0,2}|h{0,2})?[diouxXeEfFgGaAcsSpn@]/)
        raw.each_with_index do |placeholder, i|
          type_hint = case placeholder
                      when /%.*[di]/ then "a number"
                      when /%.*[fFeEgGaA]/ then "a decimal number"
                      when /%.*[@sS]/ then "a string value"
                      else "a value"
                      end
          descriptions << "#{placeholder} — #{type_hint}"
        end

        "This string contains #{raw.size} placeholder(s) that must be preserved in translation:\n" +
          descriptions.map { |d| "- #{d}" }.join("\n")
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
          match = text.match(/```(?:json)?\s*(\{[^`]+\})\s*```/m)
          return match[1] if match
        end

        # Find first { and try to parse valid JSON from it
        start = text.index('{')
        return nil unless start

        # Walk backwards from end looking for matching }
        text.length.downto(start + 1) do |i|
          next unless text[i - 1] == '}'
          candidate = text[start...i]
          begin
            Oj.load(candidate) # validate it parses
            return candidate
          rescue Oj::ParseError
            next
          end
        end
        nil
      end
    end
  end
end
