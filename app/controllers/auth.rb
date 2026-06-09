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
          request_data = signed_request_data!(routing)
          AuthenticateAccountService.call(request_data).to_json
        rescue AuthenticateAccountService::UnauthorizedError
          Api.logger.warn('Authentication failed: invalid credentials')
          routing.halt 401, { message: 'Invalid credentials' }.to_json
        end
      end

      routing.is 'register' do
        # POST api/v1/auth/register
        routing.post do
          registration = signed_request_data!(routing)
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

      routing.is 'sso' do
        # POST api/v1/auth/sso
        routing.post do
          request = signed_request_data!(routing)
          provider = request.fetch(:provider, 'google')
          routing.halt 400, { message: 'Unsupported SSO provider' }.to_json unless provider == 'google'
          unless request[:id_token].to_s.strip != '' && request[:jwks].is_a?(Hash)
            routing.halt 400, { message: 'Invalid SSO request' }.to_json
          end

          AuthenticateSsoAccountService.call(
            id_token: request[:id_token],
            jwks: request[:jwks]
          ).to_json
        rescue KeyError
          routing.halt 400, { message: 'Invalid SSO request' }.to_json
        rescue AuthenticateSsoAccountService::UnauthorizedError => e
          Api.logger.warn("SSO authentication failed: #{e.message}")
          routing.halt 401, { message: 'Invalid SSO token' }.to_json
        end
      end
    end

    private

    def signed_request_data!(routing)
      HttpRequest.new(routing).signed_body_data
    rescue SignedRequest::VerificationError
      routing.halt 403, { message: 'Must sign request' }.to_json
    end
  end
end
