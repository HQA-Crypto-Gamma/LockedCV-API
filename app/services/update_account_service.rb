# frozen_string_literal: true

module LockedCV
  # Updates editable account profile fields.
  class UpdateAccountService
    class AccountNotFoundError < StandardError; end
    class NotAuthorizedError < StandardError; end

    EDITABLE_FIELDS = %i[
      email phone_number first_name last_name birthday address identification_numbers
    ].freeze

    def self.call(current_account:, account_data:, auth_scope: AuthScope.new)
      account = FindAccountService.call(account_id: current_account&.id)
      raise AccountNotFoundError unless account
      raise NotAuthorizedError unless AccountPolicy.new(current_account, account, auth_scope:).update?

      account.update(editable_data(account_data))
      account
    end

    def self.editable_data(account_data)
      account_data.slice(*EDITABLE_FIELDS)
    end
    private_class_method :editable_data
  end
end
