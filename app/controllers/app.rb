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

    route do |routing| # rubocop:disable Metrics/BlockLength
      response['Content-Type'] = 'application/json'
      routing.root do
        { message: 'LockedCV API up at /api/v1' }.to_json
      end

      routing.on 'api' do
        routing.on 'v1' do
          routing.on 'personal_data' do
            # GET api/v1/personal_data/[id]
            routing.get String do |id|
              PersonalData.find(id).to_json
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
              if new_doc.save
                response.status = 201
                { message: 'Personal data saved', id: new_doc.id }.to_json
              else
                routing.halt 400, { message: 'Could not save personal data' }.to_json
              end
            end
          end
        end
      end
    end
  end
end
