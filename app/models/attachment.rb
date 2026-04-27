# frozen_string_literal: true

require 'json'
require 'sequel'

module LockedCV
  # Sequel model for attachments table
  class Attachment < Sequel::Model(:attachments)
    plugin :timestamps
    plugin :association_dependencies
    plugin :whitelist_security
    set_allowed_columns :attachment_name, :route

    many_to_one :account, class: :'LockedCV::Account', key: :account_id
    one_to_one :sensitive_data, class: :'LockedCV::SensitiveData', key: :attachment_id
    add_association_dependencies sensitive_data: :destroy

    def owner
      accounts_in_role('owner').first
    end

    def viewers_masked
      accounts_in_role('viewer_masked')
    end

    def viewers_full
      accounts_in_role('viewer_full')
    end

    def accounts_in_role(role_name)
      role = Role.first(name: role_name)
      return [] unless role

      role.accounts
    end
    private :accounts_in_role

    # rubocop:disable Metrics/MethodLength
    def to_json(options = {})
      JSON(
        {
          data: {
            type: 'attachment',
            attributes: {
              id:,
              attachment_name:,
              route:
            }
          },
          included: {
            account:
          }
        },
        options
      )
    end
    # rubocop:enable Metrics/MethodLength
  end
end
