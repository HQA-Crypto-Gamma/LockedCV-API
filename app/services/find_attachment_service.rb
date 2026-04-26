# frozen_string_literal: true

module LockedCV
  # Finds an attachment scoped to a specific account
  class FindAttachmentService
    def self.call(account_id:, attachment_id:)
      Attachment.where(account_id: account_id.to_s, id: attachment_id.to_s).first
    end
  end
end
