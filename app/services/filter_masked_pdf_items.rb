# frozen_string_literal: true

module LockedCV
  # Validates frontend mask selections and filters PDF sensitive items/matches.
  class FilterMaskedPdfItems
    class InvalidSelectionError < StandardError; end

    ALIASES = {
      'name' => %w[full_name first_name last_name name],
      'tel' => %w[phone phone_number tel],
      'id' => %w[identification_number identification_numbers id id_number],
      'identification_numbers' => %w[identification_number identification_numbers id id_number]
    }.freeze
    BASE_LABELS = %w[
      full_name first_name last_name name email phone phone_number tel birthday address
      identification_number identification_numbers id id_number
    ].freeze
    ALLOWED_LABELS = (BASE_LABELS + ALIASES.keys + ALIASES.values.flatten).uniq.freeze

    def self.validate(selected_labels)
      new(selected_labels:).selected_labels
    end

    def self.items(items:, selected_labels:)
      new(selected_labels:).items(items)
    end

    def self.matches(matches:, selected_labels:)
      new(selected_labels:).matches(matches)
    end

    def initialize(selected_labels:)
      @selected_labels = normalize_selection(selected_labels)
    end

    def items(items)
      return items if selected_labels.nil?

      items.select { |item| selected?(item_identifiers(item)) }
    end

    def matches(matches)
      return matches if selected_labels.nil?

      matches.select { |match| selected?(match_identifiers(match)) }
    end

    attr_reader :selected_labels

    private

    def normalize_selection(selected_labels)
      return nil if selected_labels.nil?
      raise InvalidSelectionError, 'selected_labels must be an array' unless selected_labels.is_a?(Array)

      selected_labels.map { |label| normalize_label(label) }.tap do |labels|
        unknown = labels - ALLOWED_LABELS
        raise InvalidSelectionError, "Unsupported selected_labels: #{unknown.join(', ')}" unless unknown.empty?
      end
    end

    def normalize_label(label)
      raise InvalidSelectionError, 'selected_labels must contain strings' unless label.is_a?(String)

      label.strip.downcase
    end

    def selected?(identifiers)
      expanded_selection.intersect?(identifiers)
    end

    def expanded_selection
      @expanded_selection ||= selected_labels.flat_map { |label| [label] + ALIASES.fetch(label, []) }.uniq
    end

    def item_identifiers(item)
      field_name = value_for(item, :field_name)
      kind = value_for(item, :kind)
      label = value_for(item, :label)
      normalize_identifiers([field_name, kind, label == 'MASK' ? nil : label])
    end

    def match_identifiers(match)
      field_name = value_for(match, :type)
      kind = BuildPdfplumberSensitiveItems::KINDS.fetch(field_name.to_s, field_name.to_s)
      label = BuildPdfplumberSensitiveItems::LABELS.fetch(kind, nil)
      normalize_identifiers([field_name, kind, label])
    end

    def value_for(hash, key)
      hash[key] || hash[key.to_s]
    end

    def normalize_identifiers(values)
      values.compact.flat_map do |value|
        normalized = value.to_s.strip.downcase
        [normalized] + ALIASES.fetch(normalized, [])
      end.uniq
    end
  end
end
