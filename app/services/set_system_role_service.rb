# frozen_string_literal: true

module LockedCV
  # Assigns one system role while removing the other mutually exclusive system roles.
  class SetSystemRoleService
    Result = Struct.new(:account, :created, keyword_init: true) do
      alias_method :created?, :created
    end

    def self.call(account:, role_name:)
      role = Role.first(name: role_name)
      already_assigned = account.system_roles_dataset.where(name: role_name).any?

      remove_other_system_roles(account, role_name)
      account.add_system_role(role) unless already_assigned

      Result.new(account:, created: !already_assigned)
    end

    def self.remove_other_system_roles(account, selected_role_name)
      account.system_roles_dataset
             .where(name: Role::SYSTEM_ROLES - [selected_role_name])
             .all
             .each { |role| account.remove_system_role(role) }
    end
    private_class_method :remove_other_system_roles
  end
end
