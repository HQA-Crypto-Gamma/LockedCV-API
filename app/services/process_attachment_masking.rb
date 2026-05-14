# frozen_string_literal: true

module LockedCV
  # Runs the Stage 1 attachment PDF text masking pipeline.
  class ProcessAttachmentMasking
    class AttachmentNotFoundError < StandardError; end

    def self.call(account_id:, attachment_id:)
      attachment = FindAttachmentService.call(account_id:, attachment_id:)
      raise AttachmentNotFoundError unless attachment

      masked_result(attachment:, attachment_id:)
    end

    def self.masked_result(attachment:, attachment_id:)
      pdf_path = ResolveAttachmentPath.call(route: attachment.route)
      text = ExtractPdf.text(pdf_path)
      sensitive_data = FindSensitiveDataService.call(attachment_id:)
      matches = MaskSensitiveText.matches_for_masking(text:, sensitive_data:)
      masked_text = MaskSensitiveText.call(text:, matches:)

      {
        attachment_id: attachment.id,
        masked_text:,
        matches:
      }
    end
    private_class_method :masked_result
  end
end
