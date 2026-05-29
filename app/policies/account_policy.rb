# frozen_string_literal: true

module LockedCV
  # Authorization policy for account resources.
  class AccountPolicy
    attr_reader :current_account, :account

    def initialize(current_account, account = current_account)
      @current_account = current_account
      @account = account
    end

    def view?
      same_account? || admin?
    end

    def update?
      same_account?
    end

    def change_password?
      same_account?
    end

    def delete?
      admin? && !same_account?
    end

    def assign_system_role?
      admin? && !same_account?
    end

    def summary
      {
        can_view: view?,
        can_update: update?,
        can_change_password: change_password?,
        can_delete: delete?,
        can_assign_system_role: assign_system_role?
      }
    end

    def capabilities
      {
        can_manage_accounts: admin?,
        can_manage_system_roles: admin?,
        can_upload_attachments: AttachmentPolicy.new(current_account, nil).upload?
      }
    end

    private

    def same_account?
      current_account&.id == account&.id
    end

    def admin?
      current_account&.admin?
    end
  end
end
