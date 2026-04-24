# frozen_string_literal: true

module LockedCV
  # Finds an attachment scoped to a specific user
  class FindAttachmentService
    def self.call(user_id:, attachment_id:)
      Attachment.where(user_id: user_id.to_s, id: attachment_id.to_s).first
    end
  end
end
