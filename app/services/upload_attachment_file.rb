# frozen_string_literal: true

module LockedCV
  # Stores an uploaded PDF and creates the attachment metadata record.
  class UploadAttachmentFile
    class NotAuthorizedError < StandardError; end

    def self.call(current_account:, uploaded_file:, original_filename: nil, auth_scope: AuthScope.new())
      new(current_account:, uploaded_file:, original_filename:, auth_scope:).call
    end

    def initialize(current_account:, uploaded_file:, original_filename: nil, auth_scope: AuthScope.new())
      @current_account = current_account
      @uploaded_file = uploaded_file
      @original_filename = original_filename.to_s.strip
      @auth_scope = auth_scope
    end

    def call
      raise NotAuthorizedError unless AttachmentPolicy.new(current_account, nil, auth_scope:).upload?
      raise StoreAttachmentFile::MissingFileError unless uploaded_file
      raise CreateAttachmentService::AccountNotFoundError unless FindAccountService.call(account_id:)

      route = StoreAttachmentFile.call(uploaded_file:, account_id:)
      create_attachment(route:)
    rescue StandardError
      StoreAttachmentFile.delete(route:) if route
      raise
    end

    private

    attr_reader :current_account, :uploaded_file, :original_filename, :auth_scope

    def account_id
      current_account&.id
    end

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
