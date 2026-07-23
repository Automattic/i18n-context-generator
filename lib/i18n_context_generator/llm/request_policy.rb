# frozen_string_literal: true

module I18nContextGenerator
  module LLM
    # Shared retry and HTTP error handling for remote LLM providers.
    module RequestPolicy
      RequestOutcome = Data.define(:response, :retries) do
        def request_count = retries + 1
      end

      # Adds run-local attempt counters to a transport exception without
      # changing its public exception class.
      module FailureTelemetry
        attr_reader :request_count, :retries

        def record_request_failure(retries:)
          @retries = retries
          @request_count = retries + 1
          self
        end
      end
      private_constant :FailureTelemetry

      MAX_RETRIES = 2
      MAX_RETRY_DELAY = 30.0
      RETRYABLE_STATUS_CODES = [408, 409, 425, 429, 500, 502, 503, 504, 529].freeze
      TRANSIENT_NETWORK_ERRORS = [
        Net::OpenTimeout,
        Net::ReadTimeout,
        Timeout::Error,
        EOFError,
        SocketError,
        Errno::ECONNABORTED,
        Errno::ECONNREFUSED,
        Errno::ECONNRESET,
        Errno::EHOSTUNREACH,
        Errno::ENETUNREACH,
        Errno::ETIMEDOUT,
        OpenSSL::SSL::SSLError
      ].freeze

      protected

      def request_with_retries(uri:)
        retries = 0

        loop do
          response = yield
          return RequestOutcome.new(response: response, retries: retries) unless retryable_response?(response) && retries < MAX_RETRIES

          retries += 1
          delay = retry_delay(response, retries)
          reset_http_session(uri)
          sleep(delay)
        rescue *TRANSIENT_NETWORK_ERRORS => e
          if retries >= MAX_RETRIES
            e.extend(FailureTelemetry).record_request_failure(retries: retries)
            raise
          end

          retries += 1
          reset_http_session(uri)
          sleep(retry_delay(nil, retries))
          retry
        end
      end

      def retryable_response?(response)
        status = response.code.to_i
        RETRYABLE_STATUS_CODES.include?(status)
      end

      def retry_delay(response, retry_number)
        retry_after = parse_retry_after(response&.[]('retry-after'))
        return [retry_after, MAX_RETRY_DELAY].min if retry_after

        base = 0.5 * (2**(retry_number - 1))
        [base + (rand * 0.25), MAX_RETRY_DELAY].min
      end

      def parse_retry_after(value)
        return nil if value.nil? || value.to_s.strip.empty?

        numeric = Float(value, exception: false)
        return [numeric, 0].max if numeric&.finite?

        [Time.httpdate(value) - Time.now, 0].max
      rescue ArgumentError
        nil
      end

      def http_error_result(response, retries: 0)
        telemetry = request_telemetry(retries: retries)
        case response.code.to_i
        when 401
          ContextResult.new(
            description: 'Authentication failed',
            error: 'Provider rejected the API credentials',
            **telemetry
          )
        when 429
          ContextResult.new(
            description: 'Rate limited',
            error: 'Rate limit exceeded - try reducing concurrency',
            **telemetry
          )
        else
          ContextResult.new(description: 'API error', error: provider_error_message(response), **telemetry)
        end
      end

      def provider_error_message(response)
        body = JSON.parse(response.body)
        return "HTTP #{response.code}" unless body.is_a?(Hash)

        message = body.dig('error', 'message') || body['message']
        return "HTTP #{response.code}" unless message.is_a?(String) && !message.empty?

        message.gsub(/[\u0000-\u001F\u007F]/, ' ')[0, 500]
      rescue JSON::ParserError, TypeError
        "HTTP #{response.code}"
      end

      def request_telemetry(retries:)
        { request_count: retries + 1, retries: retries }
      end

      def failure_request_telemetry(error, outcome:)
        return request_telemetry(retries: outcome.retries) if outcome
        return { request_count: error.request_count, retries: error.retries } if
          error.respond_to?(:request_count) && error.respond_to?(:retries)

        {}
      end

      def reset_http_session(uri)
        sessions = Thread.current.thread_variable_get(http_sessions_key)
        return unless sessions

        http = sessions.delete([uri.scheme, uri.host, uri.port])
        http.finish if http&.started?
      rescue IOError, SystemCallError
        nil
      end
    end
  end
end
