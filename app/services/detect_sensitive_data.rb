# frozen_string_literal: true

module LockedCV
  # Detects sensitive personal data in extracted attachment text.
  class DetectSensitiveData
    PATTERNS = {
      email: /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i,
      phone_number: /\b(?:\+?\d{1,3}[-.\s]?)?(?:\(?\d{2,4}\)?[-.\s]?)?\d{3,4}[-.\s]?\d{3,4}\b/,
      birthday: %r{\b(?:\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}[-/]\d{1,2}[-/]\d{4})\b},
      identification_number: /\b[A-Z][12]\d{8}\b/i
    }.freeze

    def self.call(text:)
      matches = PATTERNS.flat_map { |type, pattern| matches_for(text, type, pattern) }
      matches.sort_by { |match| match[:start] }
    end

    def self.matches_for(text, type, pattern)
      text.to_enum(:scan, pattern).map do
        match = Regexp.last_match
        {
          type:,
          value: match[0],
          start: match.begin(0),
          end: match.end(0)
        }
      end
    end
    private_class_method :matches_for
  end
end
