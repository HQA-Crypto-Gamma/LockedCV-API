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

      authenticated_response(account)
    end

    def self.authenticated_response(account)
      {
        data: {
          type: 'authenticated_account',
          attributes: authenticated_account(account)
        }
      }
    end
    private_class_method :authenticated_response

    def self.authenticated_account(account)
      {
        id: account.id,
        username: account.username,
        email: account.email,
        roles: account.system_roles.map(&:name),
        auth_token: auth_token_for(account)
      }
    end
    private_class_method :authenticated_account

    def self.auth_token_for(account)
      AuthToken.new(
        'account_id' => account.id,
        'username' => account.username,
        'email' => account.email
      ).to_s
    end
    private_class_method :auth_token_for
  end
end
