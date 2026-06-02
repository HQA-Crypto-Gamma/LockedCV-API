# frozen_string_literal: true

module LockedCV
  # Shared username rules for API-created accounts.
  module UsernameRules
    REGEX = /\A[A-Za-z0-9][A-Za-z0-9._-]{2,38}[A-Za-z0-9]\z/
    MIN_LENGTH = 4
    MAX_LENGTH = 40

    module_function

    def valid?(username)
      REGEX.match?(username.to_s)
    end

    def from_email(email)
      normalize(email.to_s.split('@').first)
    end

    def normalize(value)
      base = value.to_s.downcase
                  .gsub(/[^a-z0-9._-]+/, '-')
                  .gsub(/\A[^a-z0-9]+|[^a-z0-9]+\z/, '')
                  .slice(0, MAX_LENGTH)
      return nil if base.to_s.empty?

      base = "#{base}-sso" if base.length < MIN_LENGTH
      base = trim_trailing_separator(base)
      valid?(base) ? base : nil
    end

    def trim_trailing_separator(value)
      value.gsub(/[^a-z0-9]+\z/, '')
    end
  end
end
