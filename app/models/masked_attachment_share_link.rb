# frozen_string_literal: true

require 'json'
require 'sequel'

module LockedCV
  # Reusable token that grants access to one saved masked attachment.
  class MaskedAttachmentShareLink < Sequel::Model(:masked_attachment_share_links)
    plugin :timestamps
    plugin :whitelist_security
    set_allowed_columns :token, :attachment_id, :masked_attachment_id, :creator_account_id, :expires_at, :revoked_at

    many_to_one :attachment, class: :'LockedCV::Attachment', key: :attachment_id
    many_to_one :masked_attachment, class: :'LockedCV::MaskedAttachment', key: :masked_attachment_id
    many_to_one :creator_account, class: :'LockedCV::Account', key: :creator_account_id

    def active?
      revoked_at.nil? && (expires_at.nil? || expires_at.to_time > Time.now)
    end

    def share_url
      "/share/masked-attachments/#{token}"
    end

    def to_h
      {
        type: 'masked_attachment_share_link',
        attributes: attributes_hash
      }
    end

    def to_json(options = {})
      JSON({ data: to_h }, options)
    end

    def attributes_hash
      {
        token:,
        attachment_id:,
        masked_attachment_id:,
        share_url:,
        expires_at:,
        revoked_at:
      }
    end
  end
end
