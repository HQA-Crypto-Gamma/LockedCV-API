# frozen_string_literal: true

require 'roda'
require_relative 'app'

module LockedCV
  # Account-scoped API routes
  class Api < Roda
    route('accounts') do |routing|
      @account_route = "#{@api_root}/accounts"

      routing.on String do |account_id|
        routing.on 'system_roles' do
          routing.on String do |role_name|
            # PUT api/v1/accounts/[username]/system_roles/[role_name]
            routing.put do
              body = HttpRequest.new(routing).body_data
              current_account_id = body[:current_account_id]
              routing.halt(401, { message: 'Missing current_account_id' }.to_json) unless current_account_id

              result = AssignSystemRoleService.call(
                current_account_id:, target_username: account_id, role_name:
              )

              response.status = result.created? ? 201 : 200
              { message: 'System role assigned', data: result.account }.to_json
            rescue AssignSystemRoleService::NotAuthorizedError => e
              routing.halt 403, { message: e.message }.to_json
            rescue AssignSystemRoleService::UnknownRoleError
              routing.halt 400, { message: 'Unknown system role' }.to_json
            rescue AssignSystemRoleService::UnknownAccountError
              routing.halt 404, { message: 'Account not found' }.to_json
            rescue StandardError => e
              Api.logger.error "UNKNOWN ERROR: #{e.message}"
              routing.halt 500, { message: 'Database error' }.to_json
            end
          end
        end

        routing.on 'attachments' do
          @attachment_route = "#{@account_route}/#{account_id}/attachments"

          routing.on 'upload' do
            # POST api/v1/accounts/[account_id]/attachments/upload
            routing.post do
              uploaded_file = routing.params['file']
              raise StoreAttachmentFile::MissingFileError unless uploaded_file

              account = FindAccountService.call(account_id:)
              raise CreateAttachmentService::AccountNotFoundError unless account

              original_filename = uploaded_file[:filename] || uploaded_file['filename']
              route = StoreAttachmentFile.call(uploaded_file:, account_id:)
              begin
                attachment = CreateAttachmentService.call(
                  account_id:,
                  attachment_data: {
                    attachment_name: original_filename,
                    route:
                  }
                )
              rescue StandardError
                StoreAttachmentFile.delete(route:)
                raise
              end

              response.status = 201
              response['Location'] = "#{@attachment_route}/#{attachment.id}"
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
          end

          routing.on String do |attachment_id|
            routing.on 'masked_text' do
              # GET api/v1/accounts/[account_id]/attachments/[attachment_id]/masked_text
              routing.get do
                result = ProcessAttachmentMasking.call(account_id:, attachment_id:)

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
              # POST api/v1/accounts/[account_id]/attachments/[attachment_id]/masked_attachments
              routing.post do
                masked_attachment = ExportMaskedPdf.call(account_id:, attachment_id:)

                response.status = 201
                response['Location'] =
                  "#{@attachment_route}/#{attachment_id}/masked_attachments/#{masked_attachment.id}"
                { message: 'Masked attachment saved', data: masked_attachment }.to_json
              rescue ExportMaskedPdf::AttachmentNotFoundError
                routing.halt 404, { message: 'Attachment not found' }.to_json
              rescue ExportMaskedPdf::ExportError, StandardError => e
                Api.logger.error "PDF EXPORT ERROR: #{e.message}"
                routing.halt 400, { message: 'Could not export masked attachment' }.to_json
              end
            end

            routing.on 'sensitive_data' do
              @sensitive_data_route = "#{@attachment_route}/#{attachment_id}/sensitive_data"

              # GET api/v1/accounts/[account_id]/attachments/[attachment_id]/sensitive_data
              routing.get do
                attachment = FindAttachmentService.call(account_id:, attachment_id:)
                raise('Attachment not found') unless attachment

                sensitive_data = FindSensitiveDataService.call(attachment_id:)
                sensitive_data ? sensitive_data.to_json : raise('Sensitive data not found')
              rescue StandardError
                routing.halt 404, { message: 'Sensitive data not found' }.to_json
              end

              # POST api/v1/accounts/[account_id]/attachments/[attachment_id]/sensitive_data
              routing.post do
                new_data = HttpRequest.new(routing).body_data
                new_doc = CreateSensitiveDataService.call(
                  account_id:,
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

            # GET api/v1/accounts/[account_id]/attachments/[attachment_id]
            routing.get do
              attachment = FindAttachmentService.call(account_id:, attachment_id:)
              attachment ? attachment.to_json : raise('Attachment not found')
            rescue StandardError
              routing.halt 404, { message: 'Attachment not found' }.to_json
            end
          end

          # GET api/v1/accounts/[account_id]/attachments
          routing.get do
            account = FindAccountService.call(account_id:)
            raise('Account not found') unless account

            output = { data: account.attachments }
            JSON.pretty_generate(output)
          rescue StandardError
            routing.halt 404, { message: 'Could not find attachments' }.to_json
          end

          # POST api/v1/accounts/[account_id]/attachments
          routing.post do
            new_data = HttpRequest.new(routing).body_data
            new_attachment = CreateAttachmentService.call(
              account_id:,
              attachment_data: new_data
            )

            if new_attachment
              response.status = 201
              response['Location'] = "#{@attachment_route}/#{new_attachment.id}"
              { message: 'Attachment saved', data: new_attachment }.to_json
            else
              routing.halt 400, { message: 'Could not save attachment' }.to_json
            end
          rescue Sequel::MassAssignmentRestriction
            Api.logger.warn("MASS_ASSIGNMENT_ATTEMPT keys=#{new_data.keys}")
            routing.halt 400, { message: 'Illegal attributes' }.to_json
          rescue StandardError => e
            Api.logger.error "UNKNOWN ERROR: #{e.message}"
            routing.halt 500, { message: 'Database error' }.to_json
          end
        end

        routing.on 'password' do
          # PUT api/v1/accounts/[account_id]/password
          routing.put do
            password_data = HttpRequest.new(routing).body_data
            ChangePasswordService.call(account_id:, password_data:)

            { message: 'Password updated' }.to_json
          rescue ChangePasswordService::AccountNotFoundError
            routing.halt 404, { message: 'Account not found' }.to_json
          rescue ChangePasswordService::InvalidCurrentPasswordError
            routing.halt 400, { message: 'Current password is incorrect' }.to_json
          rescue ChangePasswordService::InvalidPasswordError
            routing.halt 400, { message: 'Password is required' }.to_json
          rescue StandardError => e
            Api.logger.error "UNKNOWN ERROR: #{e.message}"
            routing.halt 500, { message: 'Database error' }.to_json
          end
        end

        # DELETE api/v1/accounts/[account_id]
        routing.delete do
          body = HttpRequest.new(routing).body_data
          DeleteAccountService.call(
            current_account_id: body[:current_account_id],
            target_account_id: account_id
          )

          { message: 'Account deleted' }.to_json
        rescue DeleteAccountService::MissingCurrentAccountError
          routing.halt 401, { message: 'Missing current_account_id' }.to_json
        rescue DeleteAccountService::NotAuthorizedError
          routing.halt 403, { message: 'Only admins can delete accounts' }.to_json
        rescue DeleteAccountService::CannotDeleteSelfError
          routing.halt 403, { message: 'Admins cannot delete their own account' }.to_json
        rescue DeleteAccountService::AccountNotFoundError
          routing.halt 404, { message: 'Account not found' }.to_json
        rescue StandardError => e
          Api.logger.error "UNKNOWN ERROR: #{e.message}"
          routing.halt 500, { message: 'Database error' }.to_json
        end

        # PUT api/v1/accounts/[account_id]
        routing.put do
          updated_data = HttpRequest.new(routing).body_data
          account = UpdateAccountService.call(account_id:, account_data: updated_data)

          { message: 'Account updated', data: account }.to_json
        rescue UpdateAccountService::AccountNotFoundError
          routing.halt 404, { message: 'Account not found' }.to_json
        rescue Sequel::MassAssignmentRestriction
          Api.logger.warn("MASS_ASSIGNMENT_ATTEMPT keys=#{updated_data.keys}")
          routing.halt 400, { message: 'Illegal attributes' }.to_json
        rescue StandardError => e
          Api.logger.error "UNKNOWN ERROR: #{e.message}"
          routing.halt 500, { message: 'Database error' }.to_json
        end

        routing.get do
          account = FindAccountService.call(account_id:)
          account ? account.to_json : raise('Account not found')
        rescue StandardError
          routing.halt 404, { message: 'Account not found' }.to_json
        end
      end

      # GET api/v1/accounts?current_account_id=[admin_account_id]
      routing.get do
        accounts = ListAccountsService.call(
          current_account_id: routing.params['current_account_id']
        )

        output = {
          data: accounts.map do |account|
            {
              type: 'account',
              attributes: {
                id: account.id,
                username: account.username,
                email: account.email,
                roles: account.system_roles.map(&:name)
              }
            }
          end
        }
        JSON.pretty_generate(output)
      rescue ListAccountsService::MissingCurrentAccountError
        routing.halt 401, { message: 'Missing current_account_id' }.to_json
      rescue ListAccountsService::NotAuthorizedError
        routing.halt 403, { message: 'Only admins can list accounts' }.to_json
      rescue StandardError => e
        Api.logger.error "UNKNOWN ERROR: #{e.message}"
        routing.halt 500, { message: 'Database error' }.to_json
      end

      # POST api/v1/accounts
      routing.post do
        new_data = HttpRequest.new(routing).body_data
        new_doc = CreateAccountService.call(account_data: new_data)

        response.status = 201
        response['Location'] = "#{@account_route}/#{new_doc.id}"
        { message: 'Account saved', data: new_doc }.to_json
      rescue Sequel::MassAssignmentRestriction
        Api.logger.warn("MASS_ASSIGNMENT_ATTEMPT keys=#{new_data.keys}")
        routing.halt 400, { message: 'Illegal attributes' }.to_json
      rescue Sequel::UniqueConstraintViolation
        routing.halt 400, { message: 'This user is already registered' }.to_json
      rescue StandardError => e
        Api.logger.error "UNKNOWN ERROR: #{e.message}"
        routing.halt 500, { message: 'Database error' }.to_json
      end
    end
  end
end
