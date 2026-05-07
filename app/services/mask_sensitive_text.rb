# frozen_string_literal: true

module LockedCV
  # Replaces sensitive data values found in extracted attachment text with stable labels.
  class MaskSensitiveText
    LABELS = {
      first_name: '[FIRST_NAME]',
      last_name: '[LAST_NAME]',
      email: '[EMAIL]',
      phone_number: '[PHONE_NUMBER]',
      birthday: '[BIRTHDAY]',
      address: '[ADDRESS]',
      identification_number: '[IDENTIFICATION_NUMBER]',
      identification_numbers: '[IDENTIFICATION_NUMBERS]'
    }.freeze

    FIELDS = %i[
      first_name
      last_name
      email
      phone_number
      birthday
      address
      identification_numbers
    ].freeze

    SUPPLEMENTAL_PATTERN_TYPES = %i[email phone_number identification_number].freeze

    def self.call(text:, matches: nil, sensitive_data: nil)
      matches ||= matches_for_masking(text:, sensitive_data:)
      masked_text = text.dup

      matches.sort_by { |match| -match[:start] }.each do |match|
        masked_text[match[:start]...match[:end]] = LABELS.fetch(match[:type])
      end

      masked_text
    end

    def self.matches_for_masking(text:, sensitive_data:)
      sensitive_matches = matches_from_sensitive_data(text:, sensitive_data:)
      detected_matches = DetectSensitiveData.call(text:)
      pattern_matches = detected_matches
                        .select { |match| SUPPLEMENTAL_PATTERN_TYPES.include?(match[:type]) }
                        .map { |match| match.merge(source: :pattern) }

      without_overlaps(sensitive_matches + pattern_matches)
    end

    def self.matches_from_sensitive_data(text:, sensitive_data:)
      return [] unless sensitive_data

      matches = FIELDS.flat_map do |field|
        value = sensitive_data.public_send(field)
        matches_for(text, field, value)
      end

      without_overlaps(matches)
    end

    def self.matches_for(text, type, value)
      return [] if value.to_s.strip.empty?

      text.to_enum(:scan, /#{Regexp.escape(value.to_s)}/i).map do
        match = Regexp.last_match
        sensitive_match(type:, match:)
      end
    end
    private_class_method :matches_for

    def self.sensitive_match(type:, match:)
      {
        type:,
        value: match[0],
        start: match.begin(0),
        end: match.end(0),
        source: :sensitive_data
      }
    end
    private_class_method :sensitive_match

    def self.without_overlaps(matches)
      selected = matches
                 .sort_by { |match| [-(match[:end] - match[:start]), match[:start]] }
                 .each_with_object([]) do |match, selected_matches|
        selected_matches << match unless selected_matches.any? { |chosen| overlap?(match, chosen) }
      end

      selected.sort_by { |match| match[:start] }
    end
    private_class_method :without_overlaps

    def self.overlap?(left, right)
      left[:start] < right[:end] && right[:start] < left[:end]
    end
    private_class_method :overlap?
  end
end
