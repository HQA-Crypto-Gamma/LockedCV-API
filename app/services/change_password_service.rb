# frozen_string_literal: true

module LockedCV
  # Verifies the current password before replacing an account password.
  class ChangePasswordService
    class AccountNotFoundError < StandardError; end
    class InvalidCurrentPasswordError < StandardError; end
    class InvalidPasswordError < StandardError; end
    class NotAuthorizedError < StandardError; end

    def self.call(current_account:, password_data:, auth_scope: AuthScope.new)
      account = FindAccountService.call(account_id: current_account&.id)
      raise AccountNotFoundError unless account
      raise NotAuthorizedError unless AccountPolicy.new(current_account, account, auth_scope:).change_password?

      validate!(account, password_data)
      account.password = password_data[:password]
      account.save_changes
    end

    def self.validate!(account, password_data)
      raise InvalidPasswordError if password_data[:password].to_s.empty?
      raise InvalidCurrentPasswordError unless account.password?(password_data[:current_password].to_s)
    end
    private_class_method :validate!
  end
end
