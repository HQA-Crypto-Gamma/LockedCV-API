# frozen_string_literal: true

require_relative 'app'

module LockedCV
  # Attachment routes for LockedCV API
  class Api < Roda
    route('attachments', 'accounts') do |routing|
      @attachment_route = "#{@account_route}/#{@account_id}/attachments"

      routing.on String do |attachment_id|
        @attachment_id = attachment_id

        routing.multi_route('attachments')

        # GET api/v1/accounts/[account_id]/attachments/[attachment_id]
        routing.get do
          attachment = FindAttachmentService.call(account_id: @account_id, attachment_id:)
          attachment ? attachment.to_json : raise('Attachment not found')
        rescue StandardError
          routing.halt 404, { message: 'Attachment not found' }.to_json
        end
      end

      # GET api/v1/accounts/[account_id]/attachments
      routing.get do
        account = FindAccountService.call(account_id: @account_id)
        raise('Account not found') unless account

        output = { data: account.attachments }
        JSON.pretty_generate(output)
      rescue StandardError
        routing.halt 404, { message: 'Could not find attachments' }.to_json
      end

      # POST api/v1/accounts/[account_id]/attachments
      routing.post do
        new_data = JSON.parse(routing.body.read)
        new_attachment = CreateAttachmentService.call(
          account_id: @account_id,
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
  end
end
