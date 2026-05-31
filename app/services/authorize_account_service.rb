# frozen_string_literal: true

require 'json'

module LockedCV
  # Authorizes account detail access and returns a limited-scope API token.
  class AuthorizeAccountService
    class ForbiddenError < StandardError; end

    def self.call(auth:, username:, auth_scope: AuthScope::READ_ONLY)
      requester = requester_for(auth)
      account = Account.first(username:)
      raise ForbiddenError unless requester && account

      policy = AccountPolicy.new(requester, account, auth_scope: auth.scope)
      raise ForbiddenError unless policy.view?

      AuthorizedAccount.new(account_envelope(account, policy, requester), auth_scope, account_id: account.id)
    end

    def self.requester_for(auth)
      account_id = auth&.account&.dig('account_id') || auth&.account&.dig('attributes', 'id')
      account_id && Account.first(id: account_id)
    end
    private_class_method :requester_for

    def self.account_envelope(account, policy, requester)
      envelope = JSON.parse(account.to_json)
      envelope['policy'] = policy.summary
      envelope['capabilities'] = policy.capabilities if requester.id == account.id
      envelope
    end
    private_class_method :account_envelope
  end
end
