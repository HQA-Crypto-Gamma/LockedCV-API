# frozen_string_literal: true

require 'roda'
require 'json'
require_relative '../models/personal_data'

module LockedCV
  # Web controller for LockedCV API
  class Api < Roda
    plugin :environments
    plugin :halt

    configure do
      PersonalData.setup
    end

    route do |routing|
      response['Content-Type'] = 'application/json'

      routing.root do
        { message: 'LockedCV API up at /api/v1' }.to_json
      end

      @api_root = 'api/v1'
      routing.on @api_root do
        routing.on 'personal_data' do
          @personal_data_route = "#{@api_root}/personal_data"

          # GET api/v1/personal_data/[id]
          routing.get String do |id|
            personal_data = PersonalData.find(id)
            personal_data ? personal_data.to_json : raise('Personal data not found')
          rescue StandardError
            routing.halt 404, { message: 'Personal data not found' }.to_json
          end

          # GET api/v1/personal_data
          routing.get do
            output = { personal_data_ids: PersonalData.all }
            JSON.pretty_generate(output)
          end

          # POST api/v1/personal_data
          routing.post do
            new_data = JSON.parse(routing.body.read)
            new_doc = PersonalData.new(new_data)
            raise('Could not save personal data') unless new_doc.save_changes

            response.status = 201
            response['Location'] = "#{@personal_data_route}/#{new_doc.id}"
            { message: 'Personal data saved', id: new_doc.id }.to_json
          rescue StandardError
            routing.halt 400, { message: 'Could not save personal data' }.to_json
          end
        end
      end
    end
  end
end
