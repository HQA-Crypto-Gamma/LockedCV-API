# frozen_string_literal: true

require 'roda'
require 'json'
require_relative 'http_request'

module LockedCV
  # Web controller for LockedCV API
  class Api < Roda
    plugin :environments
    plugin :halt
    plugin :all_verbs
    plugin :multi_route

    route do |routing|
      response['Content-Type'] = 'application/json'

      HttpRequest.new(routing).secure? ||
        routing.halt(403, { message: 'TLS/SSL Required' }.to_json)

      begin
        @auth = HttpRequest.new(routing).authorized_account
        @auth_account = @auth&.account
      rescue AuthToken::ExpiredTokenError
        routing.halt 401, { message: 'Expired authorization token' }.to_json
      rescue AuthToken::InvalidTokenError
        routing.halt 401, { message: 'Invalid authorization token' }.to_json
      end

      routing.root do
        { message: 'LockedCV API up at /api/v1' }.to_json
      end

      routing.on 'api' do
        routing.on 'v1' do
          @api_root = 'api/v1'
          routing.multi_route
        end
      end
    end
  end
end
