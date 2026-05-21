# frozen_string_literal: true

require 'fileutils'
require 'securerandom'

module LockedCV
  # Creates a masked PDF output by rebuilding positioned text with sensitive values removed.
  #
  # This is a visual masking approximation for text-based PDFs, not formal redaction.
  class ExportMaskedPdf
    class AttachmentNotFoundError < StandardError; end
    class ExportError < StandardError; end

    def self.call(account_id:, attachment_id:)
      attachment = FindAttachmentService.call(account_id:, attachment_id:)
      raise AttachmentNotFoundError unless attachment

      new(account_id:, attachment:).call
    end

    def initialize(account_id:, attachment:)
      @account_id = account_id
      @attachment = attachment
    end

    def call
      pdf_path, matches, sensitive_items = masking_context
      route = write_masked_pdf(input_path: pdf_path, sensitive_items:)

      create_record(route:, matches:)
    rescue ResolveAttachmentPath::UnsafePathError, ResolveAttachmentPath::MissingFileError,
           ExtractPdf::FileNotFoundError, BuildPdfplumberMaskedPdf::Error, Sequel::Error => e
      raise ExportError, e.message
    end

    private

    attr_reader :account_id, :attachment

    def masking_context
      pdf_path = ResolveAttachmentPath.call(route: attachment.route)
      sensitive_data = FindSensitiveDataService.call(attachment_id: attachment.id)
      text = ExtractPdf.text(pdf_path)
      matches = MaskSensitiveText.matches_for_masking(text:, sensitive_data:)
      sensitive_items = BuildPdfplumberSensitiveItems.call(matches:, sensitive_data:)

      [pdf_path, matches, sensitive_items]
    end

    def write_masked_pdf(input_path:, sensitive_items:)
      route = output_route
      output_path = File.join(ResolveAttachmentPath::STORAGE_ROOT, route)
      FileUtils.mkdir_p(File.dirname(output_path))
      BuildPdfplumberMaskedPdf.call(input_path:, output_path:, sensitive_items:)
      route
    end

    def create_record(route:, matches:)
      masked_attachment = attachment.add_masked_attachment(attachment_name: masked_attachment_name, route:)
      create_masked_items(masked_attachment:, matches:)
      masked_attachment
    end

    def create_masked_items(masked_attachment:, matches:)
      unique_masked_items(matches).each do |match|
        create_masked_item(masked_attachment:, match:)
      end
    end

    def create_masked_item(masked_attachment:, match:)
      masked_attachment.add_masked_item(
        field_name: match[:type].to_s,
        value: match[:value],
        source: source_name(match[:source]),
        is_masked: true
      )
    end

    def unique_masked_items(matches)
      matches.each_with_object({}) do |match, items|
        key = [match[:type], match[:value], source_name(match[:source])]
        items[key] ||= match
      end.values
    end

    def source_name(source)
      source == :pattern ? 'regex' : source.to_s
    end

    def output_route
      File.join('accounts', safe_segment(account_id), 'masked', "#{output_basename}_#{SecureRandom.hex(16)}.pdf")
    end

    def output_basename
      basename = File.basename(attachment.attachment_name.to_s, '.*')
      safe = safe_segment("masked_#{basename}").downcase
      safe.empty? ? 'masked_attachment' : safe
    end

    def masked_attachment_name
      "masked_#{File.basename(attachment.attachment_name.to_s, '.*')}.pdf"
    end

    def safe_segment(value)
      value.to_s.gsub(/[^A-Za-z0-9_-]+/, '_').gsub(/\A_+|_+\z/, '')
    end
  end
end
