# frozen_string_literal: true

require 'sequel'

module LockedCV
  # Non-owner attachment access granted to a specific account.
  class AttachmentPermission < Sequel::Model(:attachment_permissions)
    ROLES = %w[viewer_masked].freeze

    plugin :timestamps
    plugin :whitelist_security
    set_allowed_columns :attachment_id, :account_id, :role

    many_to_one :attachment, class: :'LockedCV::Attachment', key: :attachment_id
    many_to_one :account, class: :'LockedCV::Account', key: :account_id

    def validate
      super
      errors.add(:role, 'is unsupported') unless ROLES.include?(role)
    end
  end
end
