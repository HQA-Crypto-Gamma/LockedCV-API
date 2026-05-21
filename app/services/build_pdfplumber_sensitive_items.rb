# frozen_string_literal: true

module LockedCV
  # Converts masking matches into pdfplumber processor payload items.
  class BuildPdfplumberSensitiveItems
    LABELS = {
      'full_name' => 'NAME',
      'first_name' => 'NAME',
      'last_name' => 'NAME',
      'email' => 'EMAIL',
      'phone' => 'TEL',
      'phone_number' => 'TEL',
      'identification_number' => 'ID',
      'identification_numbers' => 'ID',
      'id_number' => 'ID'
    }.freeze

    KINDS = {
      'identification_numbers' => 'id_number'
    }.freeze

    def self.call(matches:, sensitive_data:)
      new(matches:, sensitive_data:).call
    end

    def initialize(matches:, sensitive_data:)
      @matches = matches
      @sensitive_data = sensitive_data
    end

    def call
      full_name_items + match_items
    end

    private

    attr_reader :matches, :sensitive_data

    def full_name_items
      return [] unless sensitive_data

      full_name = [sensitive_data.first_name, sensitive_data.last_name].map(&:to_s).reject(&:empty?).join(' ')
      return [] if full_name.empty?

      [sensitive_item(field_name: 'full_name', value: full_name, kind: 'full_name')]
    end

    def match_items
      unique_matches.filter_map do |match|
        value = match[:value].to_s
        next if value.strip.empty?

        field_name = match[:type].to_s
        sensitive_item(field_name:, value:, kind: kind_for(field_name))
      end
    end

    def unique_matches
      matches.each_with_object({}) do |match, items|
        key = [match[:type].to_s, match[:value].to_s, match[:source].to_s]
        items[key] ||= match
      end.values
    end

    def sensitive_item(field_name:, value:, kind:)
      {
        field_name:,
        value:,
        kind:,
        label: LABELS.fetch(kind, 'MASK')
      }
    end

    def kind_for(field_name)
      KINDS.fetch(field_name, field_name)
    end
  end
end
