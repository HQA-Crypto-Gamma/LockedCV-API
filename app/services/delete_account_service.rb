# frozen_string_literal: true

module LockedCV
  # Deletes an account after verifying the caller has admin privileges.
  class DeleteAccountService
    class NotAuthorizedError < StandardError; end
    class AccountNotFoundError < StandardError; end
    class CannotDeleteSelfError < StandardError; end

    def self.call(current_account:, target_account_id:, auth_scope: AuthScope.new)
      target = target_account!(target_account_id)
      raise CannotDeleteSelfError if current_account&.id == target.id
      raise NotAuthorizedError unless AccountPolicy.new(current_account, target, auth_scope:).delete?

      delete_target!(target)

      target
    end

    def self.target_account!(target_account_id)
      Account.first(id: target_account_id) or raise AccountNotFoundError
    end

    def self.delete_target!(target)
      Account.db.transaction do
        target.system_roles.each { |role| target.remove_system_role(role) }
        target.destroy
      end
    end
  end
end
