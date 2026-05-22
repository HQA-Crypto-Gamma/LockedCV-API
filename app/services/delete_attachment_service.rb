# frozen_string_literal: true

module LockedCV
  # Deletes an attachment record and all stored files derived from it.
  class DeleteAttachmentService
    class AttachmentNotFoundError < StandardError; end

    def self.call(account_id:, attachment_id:)
      attachment = FindAttachmentService.call(account_id:, attachment_id:)
      raise AttachmentNotFoundError unless attachment

      routes = stored_routes_for(attachment)
      Attachment.db.transaction { attachment.destroy }
      routes.each { |route| StoreAttachmentFile.delete(route:) }

      attachment
    end

    def self.stored_routes_for(attachment)
      ([attachment.route] + attachment.masked_attachments.map(&:route)).compact
    end
    private_class_method :stored_routes_for
  end
end
