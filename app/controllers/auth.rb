# frozen_string_literal: true

require 'roda'
require_relative 'app'

module LockedCV
  # Authentication API routes
  class Api < Roda
    route('auth') do |routing|
      routing.is 'authenticate' do
        # POST api/v1/auth/authenticate
        routing.post do
          credentials = HttpRequest.new(routing).body_data
          AuthenticateAccountService.call(credentials).to_json
        rescue AuthenticateAccountService::UnauthorizedError => e
          puts [e.class, e.message].join(': ')
          routing.halt 403, { message: 'Invalid credentials' }.to_json
        end
      end
    end
  end
end
