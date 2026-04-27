# frozen_string_literal: true

module LockedCV
  # Creates sensitive data scoped to an attachment.
  class CreateSensitiveDataService
    class AttachmentNotFoundError < StandardError; end
    class SensitiveDataExistsError < StandardError; end
    class SaveError < StandardError; end

    def self.call(account_id:, attachment_id:, sensitive_data:)
      attachment = FindAttachmentService.call(account_id:, attachment_id:)
      raise AttachmentNotFoundError unless attachment
      raise SensitiveDataExistsError if FindSensitiveDataService.call(attachment_id:)

      new_doc = SensitiveData.new(sensitive_data)
      new_doc.attachment_id = attachment_id
      raise SaveError unless new_doc.save_changes

      new_doc
    end
  end
end
