# frozen_string_literal: true

require_relative 'app'

module LockedCV
  # Account routes for LockedCV API
  class Api < Roda
    route('accounts') do |routing|
      @account_route = "#{@api_root}/accounts"

      routing.on String do |account_id|
        @account_id = account_id

        routing.multi_route('accounts')

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
        new_data = JSON.parse(routing.body.read)
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
