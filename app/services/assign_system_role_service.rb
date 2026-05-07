# frozen_string_literal: true

module LockedCV
  # Assigns system roles to accounts as a minimal authorization demo
  class AssignSystemRoleService
    class UnknownRoleError < StandardError; end
    class UnknownAccountError < StandardError; end
    class NotAuthorizedError < StandardError; end

    Result = Struct.new(:account, :created, keyword_init: true) do
      alias_method :created?, :created
    end

    # NOTE: role-checking belongs in a Policy object once authorization is formalized.
    def self.call(current_account_id:, target_username:, role_name:)
      authorize_admin!(current_account_id)
      role = find_system_role!(role_name)
      target = find_target_account!(target_username)
      already_assigned = target.system_roles_dataset.where(name: role_name).any?
      target.add_system_role(role) unless already_assigned

      Result.new(account: target, created: !already_assigned)
    end

    def self.authorize_admin!(current_account_id)
      current_account = Account.first(id: current_account_id) or raise UnknownAccountError
      return if current_account.admin?

      raise NotAuthorizedError, 'Only admins can manage system roles'
    end

    def self.find_system_role!(role_name)
      raise UnknownRoleError, role_name unless Role::SYSTEM_ROLES.include?(role_name)

      Role.first(name: role_name) or raise UnknownRoleError, role_name
    end

    def self.find_target_account!(target_username)
      Account.first(username: target_username) or raise UnknownAccountError
    end
  end
end
