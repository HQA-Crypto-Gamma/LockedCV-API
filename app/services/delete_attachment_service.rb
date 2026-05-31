# frozen_string_literal: true

module LockedCV
  # Deletes an attachment record and all stored files derived from it.
  class DeleteAttachmentService
    class AttachmentNotFoundError < StandardError; end
    class NotAuthorizedError < StandardError; end

    def self.call(current_account:, attachment_id:, auth_scope: AuthScope.new())
      attachment = Attachment.first(id: attachment_id.to_s)
      raise AttachmentNotFoundError unless attachment
      raise NotAuthorizedError unless AttachmentPolicy.new(current_account, attachment, auth_scope:).delete?

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
