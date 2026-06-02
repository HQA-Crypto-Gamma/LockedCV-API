# frozen_string_literal: true

require 'securerandom'

module LockedCV
  # Authenticates a Google SSO user, creating a local member account if needed.
  class AuthenticateSsoAccountService
    class UnauthorizedError < StandardError; end

    def self.call(id_token:, jwks:)
      claims = GoogleIdToken.verify(id_token, jwks:)
      account = find_or_create_account(claims)

      AuthenticateAccountService.response_for(account)
    rescue OidcVerifier::VerificationError => e
      raise UnauthorizedError, e.message
    end

    def self.find_or_create_account(claims)
      email = verified_email(claims)
      existing = Account.first(email_hash: SecureDB.hash(email))
      return existing if existing

      CreateAccountService.call(account_data: account_data(claims, email))
    end
    private_class_method :find_or_create_account

    def self.verified_email(claims)
      email = claims['email'].to_s.strip.downcase
      raise UnauthorizedError, 'Google email is required' if email.empty?
      raise UnauthorizedError, 'Google email is not verified' unless claims['email_verified'] == true

      email
    end
    private_class_method :verified_email

    def self.account_data(_claims, email)
      {
        username: unique_username(email),
        email:,
        password: SecureRandom.hex(32)
      }
    end
    private_class_method :account_data

    def self.unique_username(email)
      base = UsernameRules.from_email(email) || "sso-#{SecureRandom.hex(4)}"
      return base unless Account.first(username: base)

      (1..).lazy.map { |suffix| "#{base}-#{suffix}" }
                .find { |candidate| Account.first(username: candidate).nil? }
    end
    private_class_method :unique_username
  end
end
