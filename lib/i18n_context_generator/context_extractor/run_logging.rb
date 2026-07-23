# frozen_string_literal: true

module I18nContextGenerator
  class ContextExtractor
    # Small logging helpers to keep the main extractor focused on orchestration.
    module RunLogging
      private

      def log_empty_entries_message
        if @config.diff_base && translation_backed_discovery?
          log "No changed translation keys found in #{@config.diff_base}...#{@config.diff_head}."
        elsif @config.diff_base && source_discovery_filtered_by_diff?
          log "No changed source localization entries found in #{@config.diff_base}...#{@config.diff_head}."
        else
          log "No #{entry_label_for_logging} found."
        end
      end

      def log_loaded_entries(count)
        log "Loaded #{count} #{entry_label_for_logging}"
        range = "#{@config.diff_base}...#{@config.diff_head}"
        log "(filtered to changes in #{range})" if @config.diff_base && translation_backed_discovery?
        log "(filtered to source changes in #{range})" if source_discovery_filtered_by_diff?
      end

      def resolved_model
        LLM::Client.default_model_for(@config.provider, configured_model: @config.model)
      end

      def log_metrics
        summary = [
          "Requests: #{@metrics.request_count}",
          "cache hits: #{@metrics.cache_hits}",
          "tokens: #{@metrics.input_tokens} in / #{@metrics.output_tokens} out",
          "retries: #{@metrics.retry_count}"
        ].join(', ')
        if @metrics.estimated_cost_usd
          summary += format(
            ', estimated cost: $%<cost>.6f (standard list prices as of %<date>s)',
            cost: @metrics.estimated_cost_usd,
            date: @metrics.cost_pricing_as_of
          )
        end
        log summary
      end

      def log(message = '')
        return if @quiet

        log_output.puts(message)
      end

      def log_output
        @configured_log_output ||
          (@config.output_stdout || workflow_stage == 'preview_diff' ? $stderr : $stdout)
      end

      def write_patch(patch)
        output = @patch_output || $stdout
        output.write(patch)
        output.write("\n") unless patch.end_with?("\n")
      end
    end
  end
end
