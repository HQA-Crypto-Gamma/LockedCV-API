# frozen_string_literal: true

require 'json'
require 'sequel'

module LockedCV
  # Models a named role (system-level or resource-level)
  class Role < Sequel::Model
    SYSTEM_ROLES = %w[admin member].freeze
    RESOURCE_ROLES = %w[owner viewer_masked viewer_full].freeze

    many_to_many :accounts, join_table: :accounts_roles

    plugin :timestamps, update_on_create: true

    def system_role?
      SYSTEM_ROLES.include?(name)
    end

    def resource_role?
      RESOURCE_ROLES.include?(name)
    end

    def to_json(options = {})
      JSON({ id:, name: }, options)
    end
  end
end
