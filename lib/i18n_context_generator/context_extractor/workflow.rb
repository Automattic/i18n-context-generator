# frozen_string_literal: true

module I18nContextGenerator
  class ContextExtractor
    # Explicit non-mutating and mutating workflow stages shared by the CLI and
    # programmatic callers.
    module Workflow
      private

      def workflow_stage
        @config.dry_run ? 'plan' : @config.workflow_stage
      end

      def pre_extraction_stage_handled?(entries)
        case workflow_stage
        when 'plan'
          log_plan(entries)
          true
        when 'check'
          check_entries(entries)
          true
        else
          false
        end
      end

      def log_plan(entries)
        label = @config.dry_run ? 'Dry run' : 'Plan'
        log "\n#{label} - would process these keys:"
        entries.first(20).each { |entry| log "  - #{entry.key}: #{truncate(entry.text, 50)}" }
        log "  ... and #{entries.size - 20} more" if entries.size > 20
        destinations = []
        destinations << (@config.output_stdout ? 'structured stdout' : @config.output_path) if @config.output_path
        destinations << 'translation write-back' if @config.write_back
        destinations << 'Swift code write-back' if @config.write_back_to_code
        log "Destinations: #{destinations.empty? ? 'none' : destinations.join(', ')}"
      end

      def check_entries(entries)
        without_usage = entries.count do |entry|
          resource_type = entry.metadata&.dig(:resource_type)
          searcher.search(entry.key, resource_type: resource_type).empty?
        end
        log "Check passed: #{entries.size} entries parsed; #{without_usage} without source usage."
      end

      def deliver_results
        if workflow_stage == 'preview_diff'
          write_configured_output
          preview_changes
        else
          apply_results
        end
      end

      def apply_results
        write_configured_output
        write_back_to_source if @config.write_back
        write_back_to_code if @config.write_back_to_code
      end

      def write_configured_output
        return unless @config.output_path

        write_output
        log "\nWrote #{@results.size} results to #{@config.output_stdout ? 'stdout' : @config.output_path}"
      end

      def preview_changes
        preview_translation_changes if @config.write_back
        preview_code_changes if @config.write_back_to_code
      end

      def preview_translation_changes
        @config.translations.each do |path|
          writer = source_writer_for(path)
          next unless writer

          relevant_results = @results.select { |result| result_matches_source_path?(result, path) }
          next if relevant_results.empty?

          patch = Writers::Preview.render(path) do |candidate_path|
            candidate_results = relevant_results.map do |result|
              ExtractionResult.new(**result.to_h.except(:source_file), source_file: candidate_path)
            end
            writer.write(candidate_results, candidate_path)
          end
          write_patch(patch) if patch
        end
      end

      def preview_code_changes
        results_by_key = build_results_by_key_for_code_write_back
        return if results_by_key.empty?

        swift_files_for_write_back.each do |swift_file|
          patch = Writers::Preview.render(swift_file) do |candidate_path|
            swift_writer.update_file(candidate_path, results_by_key)
          end
          write_patch(patch) if patch
        end
      end

      def swift_writer
        @swift_writer ||= Writers::SwiftWriter.new(
          functions: @config.swift_functions,
          context_prefix: @config.context_prefix,
          context_mode: @config.context_mode
        )
      end

      def swift_files_for_write_back
        @config.source_paths.flat_map do |source_path|
          find_swift_files(source_path, ignore_patterns: @config.ignore_patterns)
        end.uniq
      end
    end
  end
end
