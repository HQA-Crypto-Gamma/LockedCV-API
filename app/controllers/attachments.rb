# frozen_string_literal: true

require 'roda'
require_relative 'app'

module LockedCV
  # Token-scoped attachment API routes
  class Api < Roda
    route('attachments') do |routing|
      current_account = current_account!(routing)
      @attachment_route = "#{@api_root}/attachments"

      routing.on 'upload' do
        # POST api/v1/attachments/upload
        routing.post do
          upload_attachment_for(routing, account_id: current_account.id, location_base: @attachment_route)
        end
      end

      routing.on String do |attachment_id|
        routing.on 'sensitive_data' do
          @sensitive_data_route = "#{@attachment_route}/#{attachment_id}/sensitive_data"

          # GET api/v1/attachments/[attachment_id]/sensitive_data
          routing.get do
            attachment = FindAttachmentService.call(account_id: current_account.id, attachment_id:)
            raise('Attachment not found') unless attachment

            sensitive_data = FindSensitiveDataService.call(attachment_id:)
            sensitive_data ? sensitive_data.to_json : raise('Sensitive data not found')
          rescue StandardError
            routing.halt 404, { message: 'Sensitive data not found' }.to_json
          end

          # POST api/v1/attachments/[attachment_id]/sensitive_data
          routing.post do
            new_data = HttpRequest.new(routing).body_data
            new_doc = CreateSensitiveDataService.call(
              account_id: current_account.id,
              attachment_id:,
              sensitive_data: new_data
            )

            response.status = 201
            response['Location'] = "#{@sensitive_data_route}/#{new_doc.id}"
            { message: 'Sensitive data saved', data: new_doc }.to_json
          rescue CreateSensitiveDataService::AttachmentNotFoundError
            routing.halt 404, { message: 'Sensitive data not found' }.to_json
          rescue Sequel::MassAssignmentRestriction
            Api.logger.warn("MASS_ASSIGNMENT_ATTEMPT keys=#{new_data.keys}")
            routing.halt 400, { message: 'Illegal attributes' }.to_json
          rescue StandardError
            routing.halt 400, { message: 'Could not save sensitive data' }.to_json
          end
        end

        routing.on 'masked_text' do
          # GET api/v1/attachments/[attachment_id]/masked_text
          routing.get do
            result = ProcessAttachmentMasking.call(account_id: current_account.id, attachment_id:)

            {
              data: {
                type: 'masked_attachment_text',
                attributes: result
              }
            }.to_json
          rescue ProcessAttachmentMasking::AttachmentNotFoundError
            routing.halt 404, { message: 'Attachment not found' }.to_json
          rescue StandardError => e
            Api.logger.error "PDF MASKING ERROR: #{e.message}"
            routing.halt 400, { message: 'Could not mask attachment' }.to_json
          end
        end

        routing.on 'masked_attachments' do
          # POST api/v1/attachments/[attachment_id]/masked_attachments
          routing.post do
            masked_attachment = ExportMaskedPdf.call(account_id: current_account.id, attachment_id:)

            response.status = 201
            response['Location'] = "#{@attachment_route}/#{attachment_id}/masked_attachments/#{masked_attachment.id}"
            { message: 'Masked attachment saved', data: masked_attachment }.to_json
          rescue ExportMaskedPdf::AttachmentNotFoundError
            routing.halt 404, { message: 'Attachment not found' }.to_json
          rescue ExportMaskedPdf::ExportError, StandardError => e
            Api.logger.error "PDF EXPORT ERROR: #{e.message}"
            routing.halt 400, { message: 'Could not export masked attachment' }.to_json
          end
        end

        # GET api/v1/attachments/[attachment_id]
        routing.get do
          attachment = FindAttachmentService.call(account_id: current_account.id, attachment_id:)
          attachment ? attachment.to_json : raise('Attachment not found')
        rescue StandardError
          routing.halt 404, { message: 'Attachment not found' }.to_json
        end

        # DELETE api/v1/attachments/[attachment_id]
        routing.delete do
          delete_attachment_for(routing, account_id: current_account.id, attachment_id:)
        end
      end

      # GET api/v1/attachments
      routing.get do
        output = { data: current_account.attachments }
        JSON.pretty_generate(output)
      end
    end

    private

    def upload_attachment_for(routing, account_id:, location_base:)
      attachment = UploadAttachmentFile.call(
        account_id:,
        uploaded_file: routing.params['file'],
        original_filename: routing.params['original_filename']
      )

      response.status = 201
      response['Location'] = "#{location_base}/#{attachment.id}"
      { message: 'Attachment saved', data: attachment }.to_json
    rescue CreateAttachmentService::AccountNotFoundError
      routing.halt 404, { message: 'Account not found' }.to_json
    rescue StoreAttachmentFile::MissingFileError, StoreAttachmentFile::InvalidFileError,
           Sequel::ConstraintViolation
      routing.halt 400, { message: 'Could not upload attachment' }.to_json
    rescue StandardError => e
      Api.logger.error "UPLOAD ERROR: #{e.message}"
      routing.halt 400, { message: 'Could not upload attachment' }.to_json
    end

    def delete_attachment_for(routing, account_id:, attachment_id:)
      DeleteAttachmentService.call(account_id:, attachment_id:)

      { message: 'Attachment deleted' }.to_json
    rescue DeleteAttachmentService::AttachmentNotFoundError
      routing.halt 404, { message: 'Attachment not found' }.to_json
    rescue StandardError => e
      Api.logger.error "ATTACHMENT DELETE ERROR: #{e.message}"
      routing.halt 400, { message: 'Could not delete attachment' }.to_json
    end
  end
end
