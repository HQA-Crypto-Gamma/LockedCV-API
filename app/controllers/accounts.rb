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

          routing.on String do |attachment_id|
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

        # GET api/v1/accounts/[account_id]
        routing.get do
          account = FindAccountService.call(account_id:)
          account ? account.to_json : raise('Account not found')
        rescue StandardError
          routing.halt 404, { message: 'Account not found' }.to_json
        end
      end

      # GET api/v1/accounts
      # NOTE: Disabled for now (security concern: listing all accounts without auth)
      # routing.get do
      #   output = { data: Account.all }
      #   JSON.pretty_generate(output)
      # rescue StandardError
      #   routing.halt 500, { message: 'Error retrieving accounts' }.to_json
      # end

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
      rescue StandardError => e
        Api.logger.error "UNKNOWN ERROR: #{e.message}"
        routing.halt 500, { message: 'Database error' }.to_json
      end
    end
  end
end
