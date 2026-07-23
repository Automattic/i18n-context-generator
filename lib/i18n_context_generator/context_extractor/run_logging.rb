# frozen_string_literal: true

module I18nContextGenerator
  class ContextExtractor
    # Small logging helpers to keep the main extractor focused on orchestration.
    module RunLogging
      private

      def log_empty_entries_message
        if @config.diff_base && translation_backed_discovery?
          puts "No changed translation keys found in #{@config.diff_base}...#{@config.diff_head}."
        elsif @config.diff_base && source_discovery_filtered_by_diff?
          puts "No changed source localization entries found in #{@config.diff_base}...#{@config.diff_head}."
        else
          puts "No #{entry_label_for_logging} found."
        end
      end

      def log_loaded_entries(count)
        puts "Loaded #{count} #{entry_label_for_logging}"
        range = "#{@config.diff_base}...#{@config.diff_head}"
        puts "(filtered to changes in #{range})" if @config.diff_base && translation_backed_discovery?
        puts "(filtered to source changes in #{range})" if source_discovery_filtered_by_diff?
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
        summary += format(', estimated cost: $%.6f', @metrics.estimated_cost_usd) if @metrics.estimated_cost_usd
        puts summary
      end
    end
  end
end
