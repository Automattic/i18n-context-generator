# frozen_string_literal: true

module I18nContextGenerator
  RUN_METRICS_PRICES_PER_MILLION = {
    ['anthropic', 'claude-sonnet-4-6'] => { input: 3.0, output: 15.0 },
    ['openai', 'gpt-5-mini'] => { input: 0.25, output: 2.0 }
  }.freeze

  # Aggregates run-local provider and cache telemetry. Cost is an estimate based
  # on documented standard list prices for the built-in default models.
  RunMetrics = Data.define(
    :request_count, :cache_hits, :input_tokens, :output_tokens,
    :retry_count, :estimated_cost_usd, :cost_model
  ) do
    def self.from(results, provider:, model:)
      input_tokens = results.sum { |result| result.input_tokens.to_i }
      output_tokens = results.sum { |result| result.output_tokens.to_i }
      price = RUN_METRICS_PRICES_PER_MILLION[[provider.to_s, model.to_s]]
      estimated_cost = ((input_tokens * price[:input]) + (output_tokens * price[:output])) / 1_000_000.0 if price

      new(
        request_count: results.sum { |result| result.request_count.to_i },
        cache_hits: results.count(&:cache_hit),
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        retry_count: results.sum { |result| result.retries.to_i },
        estimated_cost_usd: estimated_cost&.round(8),
        cost_model: price ? model.to_s : nil
      )
    end

    def to_h
      {
        request_count: request_count,
        cache_hits: cache_hits,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        retry_count: retry_count,
        estimated_cost_usd: estimated_cost_usd,
        cost_model: cost_model
      }
    end
  end
end
