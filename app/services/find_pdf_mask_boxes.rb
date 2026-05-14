# frozen_string_literal: true

module LockedCV
  # Estimates rectangular mask boxes from PDF text fragments and sensitive values.
  class FindPdfMaskBoxes
    HORIZONTAL_PADDING = 2
    VERTICAL_PADDING = 1

    def self.call(fragments:, values:)
      new(fragments:, values:).call
    end

    def initialize(fragments:, values:)
      @fragments = fragments
      @values = values
    end

    def call
      values.flat_map do |value|
        fragments.flat_map { |fragment| boxes_for_fragment(fragment:, value:) }
      end
    end

    private

    attr_reader :fragments, :values

    def boxes_for_fragment(fragment:, value:)
      text = fragment[:text].to_s
      return [] if text.empty?

      indexes_for(text:, value:).map do |index|
        box_for_match(fragment:, value:, index:)
      end
    end

    def indexes_for(text:, value:)
      indexes = []
      offset = 0
      downcased_text = text.downcase
      downcased_value = value.downcase
      while (index = downcased_text.index(downcased_value, offset))
        indexes << index
        offset = index + downcased_value.length
      end
      indexes
    end

    def box_for_match(fragment:, value:, index:)
      width = matched_text_width(fragment:, value:)
      {
        page_number: fragment[:page_number],
        x: box_x(fragment:, index:),
        y: fragment[:y] - VERTICAL_PADDING,
        width: width + (HORIZONTAL_PADDING * 2),
        height: fragment[:height] + (VERTICAL_PADDING * 2)
      }
    end

    def box_x(fragment:, index:)
      fragment[:x] + (character_width(fragment) * index) - HORIZONTAL_PADDING
    end

    def matched_text_width(fragment:, value:)
      character_width(fragment) * value.length
    end

    def character_width(fragment)
      fragment[:width].to_f / fragment[:text].length
    end
  end
end
