# frozen_string_literal: true

require 'sequel'

module LockedCV
  # Non-owner access granted to a specific saved masked PDF.
  class MaskedAttachmentPermission < Sequel::Model(:masked_attachment_permissions)
    ROLES = %w[viewer].freeze

    plugin :timestamps
    plugin :whitelist_security
    set_allowed_columns :attachment_id, :masked_attachment_id, :account_id, :role

    many_to_one :attachment, class: :'LockedCV::Attachment', key: :attachment_id
    many_to_one :masked_attachment, class: :'LockedCV::MaskedAttachment', key: :masked_attachment_id
    many_to_one :account, class: :'LockedCV::Account', key: :account_id

    def validate
      super
      errors.add(:role, 'is unsupported') unless ROLES.include?(role)
    end
  end
end
