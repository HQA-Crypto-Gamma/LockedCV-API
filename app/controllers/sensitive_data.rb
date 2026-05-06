# frozen_string_literal: true

require_relative 'app'

module LockedCV
  # Sensitive data routes for LockedCV API
  class Api < Roda
    route('sensitive_data', 'attachments') do |routing|
      @sensitive_data_route = "#{@attachment_route}/#{@attachment_id}/sensitive_data"

      # GET api/v1/accounts/[account_id]/attachments/[attachment_id]/sensitive_data
      routing.get do
        attachment = FindAttachmentService.call(account_id: @account_id, attachment_id: @attachment_id)
        raise('Attachment not found') unless attachment

        sensitive_data = FindSensitiveDataService.call(attachment_id: @attachment_id)
        sensitive_data ? sensitive_data.to_json : raise('Sensitive data not found')
      rescue StandardError
        routing.halt 404, { message: 'Sensitive data not found' }.to_json
      end

      # POST api/v1/accounts/[account_id]/attachments/[attachment_id]/sensitive_data
      routing.post do
        new_data = JSON.parse(routing.body.read)
        new_doc = CreateSensitiveDataService.call(
          account_id: @account_id,
          attachment_id: @attachment_id,
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
  end
end
