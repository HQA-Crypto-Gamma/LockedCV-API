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
        rescue AuthenticateAccount::UnauthorizedError
          Api.logger.warn('Authentication failed: invalid credentials')
          routing.halt 403, { message: 'Invalid credentials' }.to_json
        end
      end

      routing.is 'register' do
        # POST api/v1/auth/register
        routing.post do
          registration = HttpRequest.new(routing).body_data
          VerifyRegistration.new(registration).call
          response.status = 202
          { message: 'Verification email sent' }.to_json
        rescue VerifyRegistration::InvalidRegistration => e
          routing.halt 400, { message: e.message }.to_json
        rescue VerifyRegistration::EmailProviderError => e
          Api.logger.error("Registration email failed: #{e.message}")
          routing.halt 500, { message: 'Could not send verification email' }.to_json
        rescue StandardError => e
          Api.logger.error("UNKNOWN ERROR: #{e.message}")
          routing.halt 500, { message: 'Unknown server error' }.to_json
        end
      end
    end
  end
end
