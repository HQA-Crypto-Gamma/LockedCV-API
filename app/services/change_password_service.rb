# frozen_string_literal: true

module LockedCV
  # Verifies the current password before replacing an account password.
  class ChangePasswordService
    class AccountNotFoundError < StandardError; end
    class InvalidCurrentPasswordError < StandardError; end
    class InvalidPasswordError < StandardError; end

    def self.call(account_id:, password_data:)
      account = FindAccountService.call(account_id:)
      raise AccountNotFoundError unless account

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
