# frozen_string_literal: true

module LockedCV
  # Updates editable account profile fields.
  class UpdateAccountService
    class AccountNotFoundError < StandardError; end

    EDITABLE_FIELDS = %i[
      email phone_number first_name last_name birthday address identification_numbers
    ].freeze

    def self.call(account_id:, account_data:)
      account = FindAccountService.call(account_id:)
      raise AccountNotFoundError unless account

      account.update(editable_data(account_data))
      account
    end

    def self.editable_data(account_data)
      account_data.slice(*EDITABLE_FIELDS)
    end
    private_class_method :editable_data
  end
end
