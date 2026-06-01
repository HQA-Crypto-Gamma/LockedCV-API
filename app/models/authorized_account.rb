# frozen_string_literal: true

require 'json'

module LockedCV
  # Account authorization context reconstructed from or minted into AuthToken.
  #
  # The token stores a serialized scope string; this object exposes the parsed
  # AuthScope used by controllers, policies, and services.
  class AuthorizedAccount
    attr_reader :account, :scope

    def initialize(account, auth_scope = AuthScope.new(), account_id: nil)
      @account = account
      @account_id = account_id
      @scope = parse_scope(auth_scope)
    end

    def token
      @token ||= AuthToken.new(token_payload, scope:).to_s
    end

    def to_h
      {
        type: 'authorized_account',
        attributes: {
          account:,
          auth_token: token
        }
      }
    end

    def to_json(options = {})
      JSON(to_h, options)
    end

    private

    def parse_scope(auth_scope)
      case auth_scope
      when AuthScope then auth_scope
      when nil then AuthScope.new()
      else AuthScope.new(auth_scope)
      end
    end

    def token_payload
      attrs = account_attributes
      {
        'account_id' => @account_id || attrs['id'],
        'username' => attrs['username']
      }
    end

    def account_attributes
      account.fetch('data', {}).fetch('attributes', account.fetch('attributes', account))
    end
  end
end
