# frozen_string_literal: true

require 'roda'
require 'json'

module LockedCV
  # Web controller for LockedCV API
  class Api < Roda
    plugin :environments
    plugin :halt

    def find_attachment_for_user(user_id, attachment_id)
      Attachment.where(user_id: user_id.to_s, id: attachment_id.to_s).first
    end

    def find_sensitive_data_for_attachment(attachment_id)
      SensitiveData.where(attachment_id: attachment_id.to_s).first
    end

    def log_unknown_error(route:, error:)
      Api.logger.error("UNKNOWN_ERROR route=#{route} error=#{error.class} message=#{error.message}")
    end

    route do |routing|
      response['Content-Type'] = 'application/json'

      routing.root do
        { message: 'LockedCV API up at /api/v1' }.to_json
      end

      @api_root = 'api/v1'
      routing.on @api_root do
        routing.on 'users' do
          @user_route = "#{@api_root}/users"

          routing.on String do |user_id|
            routing.on 'attachments' do
              @attachment_route = "#{@user_route}/#{user_id}/attachments"

              routing.on String do |attachment_id|
                routing.on 'sensitive_data' do
                  @sensitive_data_route = "#{@attachment_route}/#{attachment_id}/sensitive_data"

                  # GET api/v1/users/[user_id]/attachments/[attachment_id]/sensitive_data
                  routing.get do
                    attachment = find_attachment_for_user(user_id, attachment_id)
                    raise('Attachment not found') unless attachment

                    sensitive_data = find_sensitive_data_for_attachment(attachment_id)
                    sensitive_data ? sensitive_data.to_json : raise('Sensitive data not found')
                  rescue StandardError
                    routing.halt 404, { message: 'Sensitive data not found' }.to_json
                  end

                  # POST api/v1/users/[user_id]/attachments/[attachment_id]/sensitive_data
                  routing.post do
                    attachment = find_attachment_for_user(user_id, attachment_id)
                    raise('Attachment not found') unless attachment
                    raise('Sensitive data already exists') if find_sensitive_data_for_attachment(attachment_id)

                    new_data = JSON.parse(routing.body.read)
                    new_doc = SensitiveData.new(new_data)
                    new_doc.attachment_id = attachment_id
                    raise('Could not save sensitive data') unless new_doc.save_changes

                    response.status = 201
                    response['Location'] = "#{@sensitive_data_route}/#{new_doc.id}"
                    { message: 'Sensitive data saved', data: new_doc }.to_json
                  rescue Sequel::MassAssignmentRestriction
                    Api.logger.warn("MASS_ASSIGNMENT_ATTEMPT keys=#{new_data.keys}")
                    routing.halt 400, { message: 'Illegal attributes' }.to_json
                  rescue StandardError
                    routing.halt 400, { message: 'Could not save sensitive data' }.to_json
                  end
                end

                # GET api/v1/users/[user_id]/attachments/[attachment_id]
                routing.get do
                  attachment = find_attachment_for_user(user_id, attachment_id)
                  attachment ? attachment.to_json : raise('Attachment not found')
                rescue StandardError
                  routing.halt 404, { message: 'Attachment not found' }.to_json
                end
              end

              # GET api/v1/users/[user_id]/attachments
              routing.get do
                output = { data: User.find(id: user_id).attachments }
                JSON.pretty_generate(output)
              rescue StandardError
                routing.halt 404, { message: 'Could not find attachments' }.to_json
              end

              # POST api/v1/users/[user_id]/attachments
              routing.post do
                new_data = JSON.parse(routing.body.read)
                user = User.find(id: user_id)
                new_attachment = user.add_attachment(new_data)

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
                log_unknown_error(route: @attachment_route, error: e)
                routing.halt 500, { message: 'Database error' }.to_json
              end
            end

            # GET api/v1/users/[user_id]
            routing.get do
              user = User.find(id: user_id)
              user ? user.to_json : raise('User not found')
            rescue StandardError
              routing.halt 404, { message: 'User not found' }.to_json
            end
          end

          # GET api/v1/users
          # NOTE: Disabled for now (security concern: listing all users without auth)
          # routing.get do
          #   output = { data: User.all }
          #   JSON.pretty_generate(output)
          # rescue StandardError
          #   routing.halt 500, { message: 'Error retrieving users' }.to_json
          # end

          # POST api/v1/users
          routing.post do
            new_data = JSON.parse(routing.body.read)
            new_doc = User.new(new_data)
            raise('Could not save user') unless new_doc.save_changes

            response.status = 201
            response['Location'] = "#{@user_route}/#{new_doc.id}"
            { message: 'User saved', data: new_doc }.to_json
          rescue Sequel::MassAssignmentRestriction
            Api.logger.warn("MASS_ASSIGNMENT_ATTEMPT keys=#{new_data.keys}")
            routing.halt 400, { message: 'Illegal attributes' }.to_json
          rescue StandardError => e
            log_unknown_error(route: @user_route, error: e)
            routing.halt 500, { message: 'Database error' }.to_json
          end
        end
      end
    end
  end
end
