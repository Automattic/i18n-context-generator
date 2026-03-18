# frozen_string_literal: true

require 'json'
require 'net/http'

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
      SYSTEM_PROMPT = 'You are a mobile app localization expert. Analyze code usage and provide concise, specific context for translators. Respond with only valid JSON.'

      def self.for(provider)
        case provider.to_s.downcase
        when 'anthropic'
          Anthropic.new
        when 'openai'
          OpenAI.new
        when 'ollama'
          raise Error, 'Ollama provider not yet implemented'
        else
          raise Error, "Unknown LLM provider: #{provider}"
        end
      end

      def generate_context(key:, text:, matches:, model: nil, comment: nil,
                           include_file_paths: false, redact_prompts: true)
        raise NotImplementedError, 'Subclasses must implement #generate_context'
      end

      protected

      def build_prompt(key:, text:, matches:, comment: nil,
                       include_file_paths: false, redact_prompts: true)
        platform = detect_platform(matches)
        safe_comment = sanitize_prompt_text(comment, redact: redact_prompts)
        placeholder_info = detect_placeholders(text)

        <<~PROMPT
          You are analyzing a localized string from a #{platform} mobile app to help translators understand its context.

          ## Translation Key
          `#{key}`

          ## Original Text
          "#{text}"
          #{"\n## Developer Comment\n\"#{safe_comment}\"\n" if safe_comment && !safe_comment.strip.empty?}#{"\n## Format Placeholders\n#{placeholder_info}\n" if placeholder_info}
          ## Code Usage
          #{format_matches(matches, include_file_paths: include_file_paths, redact_prompts: redact_prompts)}

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
        return 'mobile' if matches.empty?

        extensions = matches.map { |m| File.extname(m.file).downcase }

        if extensions.any? { |e| ['.swift', '.m', '.mm'].include?(e) }
          'iOS'
        elsif extensions.any? { |e| ['.kt', '.java'].include?(e) }
          'Android'
        else
          'mobile'
        end
      end

      def format_matches(matches, include_file_paths:, redact_prompts:)
        matches.map.with_index do |match, i|
          scope_info = match.enclosing_scope ? " (in #{match.enclosing_scope})" : ''
          location = include_file_paths ? match.file : File.basename(match.file)
          context = sanitize_prompt_text(match.context, redact: redact_prompts)

          <<~MATCH
            ### Match #{i + 1}: #{location}:#{match.line}#{scope_info}
            ```
            #{context}
            ```
          MATCH
        end.join("\n")
      end

      def sanitize_prompt_text(text, redact:)
        return text if text.nil? || !redact

        text
          .gsub(%r{https?://\S+}i, '[REDACTED_URL]')
          .gsub(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i, '[REDACTED_EMAIL]')
          .gsub(%r{Bearer\s+[A-Za-z0-9\-._~+/]+=*}i, 'Bearer [REDACTED_TOKEN]')
          .gsub(/((?:api[_-]?key|access[_-]?token|refresh[_-]?token|secret|password)\s*[:=]\s*)"[^"]*"/i,
                '\1"[REDACTED_SECRET]"')
          .gsub(/((?:api[_-]?key|access[_-]?token|refresh[_-]?token|secret|password)\s*[:=]\s*)'[^']*'/i,
                "\\1'[REDACTED_SECRET]'")
          .gsub(/\beyJ[A-Za-z0-9\-_]+(?:\.[A-Za-z0-9\-_]+){2}\b/, '[REDACTED_TOKEN]')
          .gsub(/\b(?!\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\b)[A-Fa-f0-9]{32,}\b/, '[REDACTED_TOKEN]')
      end

      def detect_placeholders(text)
        # iOS: %@, %d, %f, %ld, %lld, %1$@, %2$d, etc.
        # Android: %s, %d, %f, %1$s, %2$d, etc.
        placeholders = text.scan(/%(?:(\d+)\$)?([#0 +'.-]*\d*(?:\.\d+)?(?:l{0,2}|h{0,2})?[diouxXeEfFgGaAcsSpn@])/)
        return nil if placeholders.empty?

        descriptions = []
        # Also gather the raw matches for display
        raw = text.scan(/%(?:\d+\$)?[#0 +'.-]*\d*(?:\.\d+)?(?:l{0,2}|h{0,2})?[diouxXeEfFgGaAcsSpn@]/)
        raw.each_with_index do |placeholder, _i|
          type_hint = case placeholder
                      when /%.*[di]/ then 'a number'
                      when /%.*[fFeEgGaA]/ then 'a decimal number'
                      when /%.*[@sS]/ then 'a string value'
                      else 'a value'
                      end
          descriptions << "#{placeholder} — #{type_hint}"
        end

        "This string contains #{raw.size} placeholder(s) that must be preserved in translation:\n" +
          descriptions.map { |d| "- #{d}" }.join("\n")
      end

      def parse_response(text)
        if text.nil? || text.empty?
          return ContextResult.new(description: 'Failed to parse response',
                                   error: 'Empty response')
        end

        # Try to extract JSON from the response
        json_text = extract_json(text)
        return ContextResult.new(description: text.strip, error: nil) unless json_text

        data = JSON.parse(json_text, symbolize_names: true)

        ContextResult.new(
          description: data[:description] || 'No description provided',
          ui_element: data[:ui_element],
          tone: data[:tone],
          max_length: data[:max_length]
        )
      rescue JSON::ParserError => e
        ContextResult.new(description: text.strip, error: "JSON parse error: #{e.message}")
      end

      def extract_json(text)
        # Try to find JSON object in the response
        # Handle both raw JSON and markdown-wrapped JSON
        if text.include?('```')
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
            JSON.parse(candidate) # validate it parses
            return candidate
          rescue JSON::ParserError
            next
          end
        end
        nil
      end

      def post_json(uri:, headers:, body:, open_timeout: 10, read_timeout: 60)
        http = http_for(uri, open_timeout: open_timeout, read_timeout: read_timeout)

        request = Net::HTTP::Post.new(
          uri.request_uri,
          { 'Content-Type' => 'application/json' }.merge(headers)
        )
        request.body = JSON.generate(body)

        http.request(request)
      end

      # Returns a persistent Net::HTTP session scoped to the current thread.
      # This preserves connection reuse without sharing a mutable Net::HTTP
      # instance across the worker pool.
      def http_for(uri, open_timeout:, read_timeout:)
        key = [uri.scheme, uri.host, uri.port]
        sessions = Thread.current.thread_variable_get(http_sessions_key) || {}
        http = sessions[key]

        if http&.started?
          http.open_timeout = open_timeout
          http.read_timeout = read_timeout
          return http
        end

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = open_timeout
        http.read_timeout = read_timeout
        http.keep_alive_timeout = 30
        http.start

        sessions[key] = http
        Thread.current.thread_variable_set(http_sessions_key, sessions)
        http
      end

      def http_sessions_key
        @http_sessions_key ||= :"txcontext_http_sessions_#{object_id}"
      end
    end
  end
end
