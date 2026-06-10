# frozen_string_literal: true

require 'fileutils'
require 'roda'
require_relative 'app'

module LockedCV
  # Token-scoped attachment API routes
  class Api < Roda
    route('attachments') do |routing|
      current_account = current_account!(routing)
      auth_scope = current_auth_scope!(routing)
      @attachment_route = "#{@api_root}/attachments"

      routing.on 'upload' do
        # POST api/v1/attachments/upload
        routing.post do
          upload_attachment_for(routing, current_account:, auth_scope:, location_base: @attachment_route)
        end
      end

      routing.on String do |attachment_id|
        routing.on 'sensitive_data' do
          @sensitive_data_route = "#{@attachment_route}/#{attachment_id}/sensitive_data"

          # GET api/v1/attachments/[attachment_id]/sensitive_data
          routing.get do
            authorized_attachment!(attachment_id, current_account, auth_scope, :view?)

            sensitive_data = FindSensitiveDataService.call(attachment_id:)
            sensitive_data ? sensitive_data.to_json : raise('Sensitive data not found')
          rescue AttachmentNotAuthorizedError, StandardError
            routing.halt 404, { message: 'Sensitive data not found' }.to_json
          end

          # POST api/v1/attachments/[attachment_id]/sensitive_data
          routing.post do
            authorized_attachment!(attachment_id, current_account, auth_scope, :view?)
            new_data = HttpRequest.new(routing).body_data
            new_doc = CreateSensitiveDataService.call(
              account_id: current_account.id,
              attachment_id:,
              sensitive_data: new_data
            )

            response.status = 201
            response['Location'] = "#{@sensitive_data_route}/#{new_doc.id}"
            { message: 'Sensitive data saved', data: new_doc }.to_json
          rescue AttachmentNotAuthorizedError, CreateSensitiveDataService::AttachmentNotFoundError
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
            authorized_attachment!(attachment_id, current_account, auth_scope, :view_masked?)
            result = ProcessAttachmentMasking.call(account_id: current_account.id, attachment_id:)

            {
              data: {
                type: 'masked_attachment_text',
                attributes: result
              }
            }.to_json
          rescue AttachmentNotAuthorizedError, ProcessAttachmentMasking::AttachmentNotFoundError
            routing.halt 404, { message: 'Attachment not found' }.to_json
          rescue StandardError => e
            Api.logger.error "PDF MASKING ERROR: #{e.message}"
            routing.halt 400, { message: 'Could not mask attachment' }.to_json
          end
        end

        routing.on 'masked_attachments' do
          routing.on 'preview' do
            # POST api/v1/attachments/[attachment_id]/masked_attachments/preview
            routing.post do
              authorized_attachment!(attachment_id, current_account, auth_scope, :view?)
              selected_labels = selected_labels_from_request(routing)
              preview_path = PreviewMaskedPdf.call(
                account_id: current_account.id,
                attachment_id:,
                selected_labels:
              )
              pdf_body = File.binread(preview_path)
              FileUtils.rm_f(preview_path)

              response.status = 200
              response['Content-Type'] = 'application/pdf'
              response['Content-Disposition'] = 'inline; filename="masked_preview.pdf"'
              pdf_body
            rescue AttachmentNotAuthorizedError, PreviewMaskedPdf::AttachmentNotFoundError
              routing.halt 404, { message: 'Attachment not found' }.to_json
            rescue JSON::ParserError, FilterMaskedPdfItems::InvalidSelectionError
              routing.halt 400, { message: 'Invalid selected labels' }.to_json
            rescue PreviewMaskedPdf::PreviewError, StandardError => e
              Api.logger.error "PDF PREVIEW ERROR: #{e.message}"
              routing.halt 400, { message: 'Could not preview masked attachment' }.to_json
            ensure
              FileUtils.rm_f(preview_path) if defined?(preview_path) && preview_path
            end
          end

          routing.on String do |masked_attachment_id|
            routing.on 'share_links' do
              # POST api/v1/attachments/[attachment_id]/masked_attachments/[masked_attachment_id]/share_links
              routing.post do
                authorized_attachment!(attachment_id, current_account, auth_scope, :view?)
                share_link = CreateMaskedAttachmentShareLink.call(
                  current_account:,
                  attachment_id:,
                  masked_attachment_id:
                )

                response.status = 201
                response['Location'] = "api/v1/masked_attachment_share_links/#{share_link.token}"
                { message: 'Masked attachment share link created', data: share_link.to_h }.to_json
              rescue AttachmentNotAuthorizedError, CreateMaskedAttachmentShareLink::MaskedAttachmentNotFoundError
                routing.halt 404, { message: 'Masked attachment not found' }.to_json
              rescue StandardError => e
                Api.logger.error "MASKED ATTACHMENT SHARE LINK CREATE ERROR: #{e.message}"
                routing.halt 400, { message: 'Could not create masked attachment share link' }.to_json
              end
            end

            routing.on 'download' do
              # GET api/v1/attachments/[attachment_id]/masked_attachments/[masked_attachment_id]/download
              routing.get do
                masked_attachment = MaskedAttachment.first(id: masked_attachment_id, attachment_id: attachment_id.to_s)
                raise AttachmentNotAuthorizedError unless masked_attachment
                unless masked_attachment_view_authorized?(masked_attachment, current_account, auth_scope)
                  raise AttachmentNotAuthorizedError
                end

                masked_path = ResolveAttachmentPath.call(route: masked_attachment.route)
                response.status = 200
                response['Content-Type'] = 'application/pdf'
                response['Content-Disposition'] = download_content_disposition(masked_attachment)
                File.binread(masked_path)
              rescue AttachmentNotAuthorizedError, ResolveAttachmentPath::UnsafePathError,
                     ResolveAttachmentPath::MissingFileError, Sequel::Error
                routing.halt 404, { message: 'Masked attachment not found' }.to_json
              rescue StandardError => e
                Api.logger.error "PDF DOWNLOAD ERROR: #{e.message}"
                routing.halt 400, { message: 'Could not download masked attachment' }.to_json
              end
            end

            routing.on 'view' do
              # GET api/v1/attachments/[attachment_id]/masked_attachments/[masked_attachment_id]/view
              routing.get do
                masked_attachment = MaskedAttachment.first(id: masked_attachment_id, attachment_id: attachment_id.to_s)
                raise AttachmentNotAuthorizedError unless masked_attachment
                unless masked_attachment_view_authorized?(masked_attachment, current_account, auth_scope)
                  raise AttachmentNotAuthorizedError
                end

                masked_path = ResolveAttachmentPath.call(route: masked_attachment.route)
                response.status = 200
                response['Content-Type'] = 'application/pdf'
                response['Content-Disposition'] = inline_content_disposition(masked_attachment)
                File.binread(masked_path)
              rescue AttachmentNotAuthorizedError, ResolveAttachmentPath::UnsafePathError,
                     ResolveAttachmentPath::MissingFileError, Sequel::Error
                routing.halt 404, { message: 'Masked attachment not found' }.to_json
              rescue StandardError => e
                Api.logger.error "PDF VIEW ERROR: #{e.message}"
                routing.halt 400, { message: 'Could not view masked attachment' }.to_json
              end
            end

            routing.on 'encrypted_download' do
              # POST api/v1/attachments/[attachment_id]/masked_attachments/[masked_attachment_id]/encrypted_download
              routing.post do
                authorized_attachment!(attachment_id, current_account, auth_scope, :view?)
                password = HttpRequest.new(routing).body_data.fetch(:password, nil)
                raise BuildEncryptedPdf::Error, 'Password is required' if password.to_s.strip.empty?

                masked_attachment = MaskedAttachment.first(id: masked_attachment_id, attachment_id: attachment_id.to_s)
                raise AttachmentNotAuthorizedError unless masked_attachment

                masked_path = ResolveAttachmentPath.call(route: masked_attachment.route)
                encrypted_path = BuildEncryptedPdf.call(input_path: masked_path, password:)
                pdf_body = File.binread(encrypted_path)
                FileUtils.rm_f(encrypted_path)

                response.status = 200
                response['Content-Type'] = 'application/pdf'
                response['Content-Disposition'] = encrypted_download_content_disposition(masked_attachment)
                pdf_body
              rescue AttachmentNotAuthorizedError, ResolveAttachmentPath::UnsafePathError,
                     ResolveAttachmentPath::MissingFileError, Sequel::Error
                routing.halt 404, { message: 'Masked attachment not found' }.to_json
              rescue StandardError => e
                Api.logger.error "PDF ENCRYPT DOWNLOAD ERROR: #{e.message}"
                routing.halt 400, { message: 'Could not encrypt masked attachment' }.to_json
              ensure
                FileUtils.rm_f(encrypted_path) if defined?(encrypted_path) && encrypted_path
              end
            end

            # DELETE api/v1/attachments/[attachment_id]/masked_attachments/[masked_attachment_id]
            routing.delete do
              delete_masked_attachment_for(
                routing,
                current_account:,
                auth_scope:,
                attachment_id:,
                masked_attachment_id:
              )
            end
          end

          # GET api/v1/attachments/[attachment_id]/masked_attachments
          routing.get do
            authorized_attachment!(attachment_id, current_account, auth_scope, :view?)
            attachment = Attachment.first(id: attachment_id.to_s)
            raise AttachmentNotAuthorizedError unless attachment

            masked_attachments = attachment.masked_attachments_dataset.reverse_order(:created_at).all
            JSON.pretty_generate(
              data: masked_attachments.map { |masked_attachment| JSON.parse(masked_attachment.to_json) }
            )
          rescue AttachmentNotAuthorizedError
            routing.halt 404, { message: 'Attachment not found' }.to_json
          end

          # POST api/v1/attachments/[attachment_id]/masked_attachments
          routing.post do
            authorized_attachment!(attachment_id, current_account, auth_scope, :view?)
            selected_labels = selected_labels_from_request(routing)
            masked_attachment = ExportMaskedPdf.call(account_id: current_account.id, attachment_id:, selected_labels:)

            response.status = 201
            response['Location'] = "#{@attachment_route}/#{attachment_id}/masked_attachments/#{masked_attachment.id}"
            { message: 'Masked attachment saved', data: masked_attachment }.to_json
          rescue AttachmentNotAuthorizedError, ExportMaskedPdf::AttachmentNotFoundError
            routing.halt 404, { message: 'Attachment not found' }.to_json
          rescue JSON::ParserError, FilterMaskedPdfItems::InvalidSelectionError
            routing.halt 400, { message: 'Invalid selected labels' }.to_json
          rescue ExportMaskedPdf::ExportError, StandardError => e
            Api.logger.error "PDF EXPORT ERROR: #{e.message}"
            routing.halt 400, { message: 'Could not export masked attachment' }.to_json
          end
        end

        # GET api/v1/attachments/[attachment_id]
        routing.get do
          attachment, policy = authorized_attachment_with_policy!(attachment_id, current_account, auth_scope, :access?)
          output = JSON.parse(attachment.to_json).merge(policy: policy.summary)

          JSON.pretty_generate(output)
        rescue StandardError
          routing.halt 404, { message: 'Attachment not found' }.to_json
        end

        # DELETE api/v1/attachments/[attachment_id]
        routing.delete do
          delete_attachment_for(routing, current_account:, auth_scope:, attachment_id:)
        end
      end

      # GET api/v1/attachments
      routing.get do
        attachments = AttachmentPolicy::AccountScope.new(current_account).viewable.reverse_order(:created_at).all
        output = {
          data: attachments.map do |attachment|
            policy = AttachmentPolicy.new(current_account, attachment, auth_scope:)
            JSON.parse(attachment.to_json).merge(policy: policy.summary)
          end
        }

        JSON.pretty_generate(output)
      end
    end

    private

    class AttachmentNotAuthorizedError < StandardError; end

    def authorized_attachment!(attachment_id, current_account, auth_scope, policy_action)
      attachment, _policy = authorized_attachment_with_policy!(
        attachment_id,
        current_account,
        auth_scope,
        policy_action
      )
      attachment
    end

    def authorized_attachment_with_policy!(attachment_id, current_account, auth_scope, policy_action)
      attachment = Attachment.first(id: attachment_id.to_s)
      policy = AttachmentPolicy.new(current_account, attachment, auth_scope:)
      return [attachment, policy] if attachment && policy.public_send(policy_action)

      raise AttachmentNotAuthorizedError
    rescue Sequel::Error
      raise AttachmentNotAuthorizedError
    end

    def halt_forbidden(routing, message)
      routing.halt 403, { message: }.to_json
    end

    def selected_labels_from_request(routing)
      selected_labels = HttpRequest.new(routing).body_data.fetch(:selected_labels, nil)
      FilterMaskedPdfItems.validate(selected_labels)
    end

    def download_content_disposition(masked_attachment)
      filename = File.basename(masked_attachment.attachment_name)
      "attachment; filename=\"#{filename}\""
    end

    def encrypted_download_content_disposition(masked_attachment)
      filename = File.basename(masked_attachment.attachment_name)
      "attachment; filename=\"encrypted_#{filename}\""
    end

    def inline_content_disposition(masked_attachment)
      filename = File.basename(masked_attachment.attachment_name)
      "inline; filename=\"#{filename}\""
    end

    def masked_attachment_view_authorized?(masked_attachment, current_account, auth_scope)
      return false unless auth_scope.can_read?(AttachmentPolicy::RESOURCE)
      return true if current_account&.id == masked_attachment.attachment&.account_id

      permission = MaskedAttachmentPermission.first(
        account_id: current_account&.id,
        attachment_id: masked_attachment.attachment_id,
        masked_attachment_id: masked_attachment.id,
        role: 'viewer'
      )
      permission&.active? || false
    end

    def upload_attachment_for(routing, current_account:, auth_scope:, location_base:)
      attachment = upload_attachment(current_account:, auth_scope:, routing:)

      response.status = 201
      response['Location'] = "#{location_base}/#{attachment.id}"
      { message: 'Attachment saved', data: attachment }.to_json
    rescue StandardError => e
      halt_upload_error(routing, e)
    end

    def upload_attachment(current_account:, auth_scope:, routing:)
      UploadAttachmentFile.call(
        current_account:,
        auth_scope:,
        uploaded_file: routing.params['file'],
        original_filename: routing.params['original_filename']
      )
    end

    def halt_upload_error(routing, error)
      status, message = upload_error_response(error)
      Api.logger.error "UPLOAD ERROR: #{error.message}" unless known_upload_error?(error)
      routing.halt status, { message: }.to_json
    end

    def upload_error_response(error)
      return [403, 'Only members can upload attachments'] if error.is_a?(UploadAttachmentFile::NotAuthorizedError)
      return [404, 'Account not found'] if error.is_a?(CreateAttachmentService::AccountNotFoundError)
      return [400, 'Could not upload attachment'] if upload_file_error?(error)

      [400, 'Could not upload attachment']
    end

    def known_upload_error?(error)
      error.is_a?(UploadAttachmentFile::NotAuthorizedError) ||
        error.is_a?(CreateAttachmentService::AccountNotFoundError) ||
        upload_file_error?(error)
    end

    def upload_file_error?(error)
      [
        StoreAttachmentFile::MissingFileError,
        StoreAttachmentFile::InvalidFileError,
        Sequel::ConstraintViolation
      ].any? do |klass|
        error.is_a?(klass)
      end
    end

    def delete_attachment_for(routing, current_account:, auth_scope:, attachment_id:)
      DeleteAttachmentService.call(current_account:, attachment_id:, auth_scope:)

      { message: 'Attachment deleted' }.to_json
    rescue DeleteAttachmentService::AttachmentNotFoundError, DeleteAttachmentService::NotAuthorizedError
      routing.halt 404, { message: 'Attachment not found' }.to_json
    rescue StandardError => e
      Api.logger.error "ATTACHMENT DELETE ERROR: #{e.message}"
      routing.halt 400, { message: 'Could not delete attachment' }.to_json
    end

    def delete_masked_attachment_for(routing, current_account:, auth_scope:, attachment_id:, masked_attachment_id:)
      DeleteMaskedAttachmentService.call(current_account:, attachment_id:, masked_attachment_id:, auth_scope:)

      { message: 'Masked attachment deleted' }.to_json
    rescue DeleteMaskedAttachmentService::MaskedAttachmentNotFoundError,
           DeleteMaskedAttachmentService::NotAuthorizedError
      routing.halt 404, { message: 'Masked attachment not found' }.to_json
    rescue StandardError => e
      Api.logger.error "MASKED ATTACHMENT DELETE ERROR: #{e.message}"
      routing.halt 400, { message: 'Could not delete masked attachment' }.to_json
    end
  end
end
