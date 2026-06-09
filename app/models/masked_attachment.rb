# frozen_string_literal: true

require 'json'
require 'sequel'

module LockedCV
  # Sequel model for masked PDF outputs.
  class MaskedAttachment < Sequel::Model(:masked_attachments)
    plugin :timestamps
    plugin :association_dependencies
    plugin :whitelist_security
    set_allowed_columns :attachment_name, :route

    many_to_one :attachment, class: :'LockedCV::Attachment', key: :attachment_id
    one_to_many :masked_items, class: :'LockedCV::MaskedItem', key: :masked_attachment_id
    one_to_many :masked_attachment_share_links,
                class: :'LockedCV::MaskedAttachmentShareLink',
                key: :masked_attachment_id
    add_association_dependencies masked_items: :destroy,
                                 masked_attachment_share_links: :destroy

    # rubocop:disable Metrics/MethodLength
    def to_json(options = {})
      JSON(
        {
          data: {
            type: 'masked_attachment',
            attributes: {
              id:,
              attachment_id:,
              attachment_name:,
              route:,
              masked_items_count: masked_items_dataset.count,
              created_at:,
              updated_at:
            }
          }
        },
        options
      )
    end
    # rubocop:enable Metrics/MethodLength
  end
end
