# frozen_string_literal: true

module LockedCV
  # Deletes one saved masked PDF version and its stored file.
  class DeleteMaskedAttachmentService
    class MaskedAttachmentNotFoundError < StandardError; end
    class NotAuthorizedError < StandardError; end

    def self.call(current_account:, attachment_id:, masked_attachment_id:, auth_scope: AuthScope.new)
      attachment = Attachment.first(id: attachment_id.to_s)
      raise MaskedAttachmentNotFoundError unless attachment
      raise NotAuthorizedError unless AttachmentPolicy.new(current_account, attachment, auth_scope:).delete?

      masked_attachment = MaskedAttachment.first(id: masked_attachment_id.to_s, attachment_id: attachment.id)
      raise MaskedAttachmentNotFoundError unless masked_attachment

      route = masked_attachment.route
      MaskedAttachment.db.transaction { masked_attachment.destroy }
      StoreAttachmentFile.delete(route:) if route

      masked_attachment
    end
  end
end
