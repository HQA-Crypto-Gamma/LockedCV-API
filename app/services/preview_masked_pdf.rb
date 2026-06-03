# frozen_string_literal: true

require 'fileutils'
require 'securerandom'

module LockedCV
  # Generates a temporary masked PDF preview without creating permanent records.
  class PreviewMaskedPdf
    class AttachmentNotFoundError < StandardError; end
    class PreviewError < StandardError; end

    PREVIEW_DIR = File.join('tmp', 'masked_previews')

    def self.call(account_id:, attachment_id:, selected_labels:)
      attachment = FindAttachmentService.call(account_id:, attachment_id:)
      raise AttachmentNotFoundError unless attachment

      new(attachment:, selected_labels:).call
    end

    def initialize(attachment:, selected_labels:)
      @attachment = attachment
      @selected_labels = selected_labels
    end

    def call
      input_path = ResolveAttachmentPath.call(route: attachment.route)
      sensitive_items = selected_sensitive_items(input_path)

      BuildPdfplumberMaskedPdf.call(input_path:, output_path: preview_path, sensitive_items:)
    rescue ResolveAttachmentPath::UnsafePathError, ResolveAttachmentPath::MissingFileError,
           ExtractPdf::FileNotFoundError, BuildPdfplumberMaskedPdf::Error => e
      raise PreviewError, e.message
    end

    private

    attr_reader :attachment, :selected_labels

    def selected_sensitive_items(input_path)
      sensitive_data = FindSensitiveDataService.call(attachment_id: attachment.id)
      text = ExtractPdf.text(input_path)
      matches = MaskSensitiveText.matches_for_masking(text:, sensitive_data:)
      sensitive_items = BuildPdfplumberSensitiveItems.call(matches:, sensitive_data:)

      FilterMaskedPdfItems.items(items: sensitive_items, selected_labels:)
    end

    def preview_path
      FileUtils.mkdir_p(PREVIEW_DIR)
      File.join(PREVIEW_DIR, "masked_preview_#{SecureRandom.uuid}.pdf")
    end
  end
end
