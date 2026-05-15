# frozen_string_literal: true

module LockedCV
  # Deletes an account after verifying the caller has admin privileges.
  class DeleteAccountService
    class MissingCurrentAccountError < StandardError; end
    class NotAuthorizedError < StandardError; end
    class AccountNotFoundError < StandardError; end
    class CannotDeleteSelfError < StandardError; end

    def self.call(current_account_id:, target_account_id:)
      raise MissingCurrentAccountError unless current_account_id

      current_account = Account.first(id: current_account_id)
      raise NotAuthorizedError unless current_account&.admin?
      raise CannotDeleteSelfError if current_account.id == target_account_id

      target = Account.first(id: target_account_id)
      raise AccountNotFoundError unless target

      Account.db.transaction do
        target.system_roles.each { |role| target.remove_system_role(role) }
        target.destroy
      end

      target
    end
  end
end
