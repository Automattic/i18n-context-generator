# frozen_string_literal: true

module I18nContextGenerator
  module Writers
    # Stable machine-output encoding shared by JSON and CSV writers.
    module ResultSerialization
      OUTPUT_SCHEMA_VERSION = 1

      private

      def result_sort_key(result)
        [result.source_file.to_s, result.translation_key.to_s, result.key]
      end

      def serialize_locations(locations)
        Array(locations).map { |location| serialize_location(location) }
      end

      def serialize_location_groups(groups)
        Array(groups).map { |group| serialize_locations(group) }
      end

      def serialize_location(location)
        return location unless location.is_a?(ChangedLocation)

        location.to_h.transform_values { |value| value.is_a?(Symbol) ? value.to_s : value }
      end
    end
  end
end
