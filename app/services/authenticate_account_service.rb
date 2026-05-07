# frozen_string_literal: true

module LockedCV
  # Find account and check password credentials
  class AuthenticateAccountService
    # Error for invalid credentials
    class UnauthorizedError < StandardError
      def initialize(credentials)
        @credentials = credentials
        super
      end

      def message
        "Invalid credentials for: #{@credentials[:username]}"
      end
    end

    def self.call(credentials)
      account = Account.first(username: credentials[:username])
      raise UnauthorizedError, credentials unless account&.password?(credentials[:password])

      account
    end
  end
end
