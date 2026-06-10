# frozen_string_literal: true

module LockedCV
  # Authorization policy for account resources.
  class AccountPolicy
    RESOURCE = 'accounts'

    attr_reader :current_account, :account, :auth_scope

    def initialize(current_account, account = current_account, auth_scope: AuthScope.new)
      @current_account = current_account
      @account = account
      @auth_scope = auth_scope
    end

    def view?
      can_read? && (same_account? || admin?)
    end

    def update?
      can_write? && same_account?
    end

    def change_password?
      can_write? && same_account?
    end

    def delete?
      can_write? && admin? && !same_account?
    end

    def assign_system_role?
      can_write? && admin? && !same_account?
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
        # Existing APP code uses this capability to show the accounts list.
        # Account deletion is authorized separately through delete?.
        can_manage_accounts: can_read? && admin?,
        can_manage_system_roles: can_write? && admin?,
        can_upload_attachments: AttachmentPolicy.new(current_account, nil, auth_scope:).upload?
      }
    end

    private

    def can_read?
      auth_scope.can_read?(RESOURCE)
    end

    def can_write?
      auth_scope.can_write?(RESOURCE)
    end

    def same_account?
      current_account&.id == account&.id
    end

    def admin?
      current_account&.admin?
    end
  end
end
