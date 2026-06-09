# frozen_string_literal: true

require 'roda'
require_relative 'app'

module LockedCV
  # API routes for masked PDFs shared with the current account.
  class Api < Roda
    route('shared_masked_attachments') do |routing|
      current_account = current_account!(routing)

      # GET api/v1/shared_masked_attachments
      routing.get do
        permissions = MaskedAttachmentPermission
                      .where(account_id: current_account.id, role: 'viewer')
                      .reverse_order(:created_at)
                      .all

        JSON.pretty_generate(
          data: permissions.filter_map { |permission| shared_masked_attachment_json(permission) }
        )
      end
    end

    private

    def shared_masked_attachment_json(permission)
      masked_attachment = permission.masked_attachment
      attachment = permission.attachment
      return unless masked_attachment && attachment

      {
        data: {
          type: 'shared_masked_attachment',
          attributes: {
            attachment_id: attachment.id,
            masked_attachment_id: masked_attachment.id,
            attachment_name: attachment.attachment_name,
            masked_attachment_name: masked_attachment.attachment_name,
            masked_items_count: masked_attachment.masked_items_dataset.count,
            shared_at: permission.created_at,
            created_at: masked_attachment.created_at
          }
        }
      }
    end
  end
end
