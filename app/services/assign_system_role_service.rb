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
    def self.call(current_account:, target_username:, role_name:)
      authorize_admin!(current_account)
      find_system_role!(role_name)
      target = find_target_account!(target_username)

      result = SetSystemRoleService.call(account: target, role_name:)
      Result.new(account: result.account, created: result.created?)
    end

    def self.authorize_admin!(current_account)
      return if current_account&.admin?

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
