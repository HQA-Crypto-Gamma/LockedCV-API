# frozen_string_literal: true

module LockedCV
  # Checks whether requested registration identifiers are still available.
  class CheckRegistrationAvailability
    class InvalidRegistration < StandardError; end

    def initialize(registration)
      @registration = registration
    end

    def call
      validate_required_fields!
      raise InvalidRegistration, 'Email already registered' unless email_available?
      raise InvalidRegistration, 'Username already taken' unless username_available?

      true
    end

    private

    def validate_required_fields!
      raise InvalidRegistration, 'Email is required' if registration_value(:email).empty?
      raise InvalidRegistration, 'Username is required' if registration_value(:username).empty?
    end

    def email_available?
      Account.first(email_hash: SecureDB.hash(registration_value(:email))).nil?
    end

    def username_available?
      Account.first(username: registration_value(:username)).nil?
    end

    def registration_value(key)
      @registration[key].to_s.strip
    end
  end
end
