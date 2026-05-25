# frozen_string_literal: true

module LockedCV
  # Stores an uploaded PDF and creates the attachment metadata record.
  class UploadAttachmentFile
    def self.call(account_id:, uploaded_file:, original_filename: nil)
      new(account_id:, uploaded_file:, original_filename:).call
    end

    def initialize(account_id:, uploaded_file:, original_filename: nil)
      @account_id = account_id
      @uploaded_file = uploaded_file
      @original_filename = original_filename.to_s.strip
    end

    def call
      raise StoreAttachmentFile::MissingFileError unless uploaded_file
      raise CreateAttachmentService::AccountNotFoundError unless FindAccountService.call(account_id:)

      route = StoreAttachmentFile.call(uploaded_file:, account_id:)
      create_attachment(route:)
    rescue StandardError
      StoreAttachmentFile.delete(route:) if route
      raise
    end

    private

    attr_reader :account_id, :uploaded_file, :original_filename

    def create_attachment(route:)
      CreateAttachmentService.call(
        account_id:,
        attachment_data: {
          attachment_name: display_filename,
          route:
        }
      )
    end

    def display_filename
      return original_filename unless original_filename.empty?

      uploaded_filename.to_s
    end

    def uploaded_filename
      return uploaded_file[:filename] if uploaded_file.respond_to?(:key?) && uploaded_file.key?(:filename)
      return uploaded_file['filename'] if uploaded_file.respond_to?(:key?) && uploaded_file.key?('filename')

      nil
    end
  end
end
