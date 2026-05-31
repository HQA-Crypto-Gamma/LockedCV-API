# frozen_string_literal: true

module LockedCV
  # HTTP Request helper methods
  class HttpRequest
    def initialize(roda_routing)
      @routing = roda_routing
    end

    def secure?
      raise 'Secure scheme not configured' unless Api.config.SECURE_SCHEME

      @routing.scheme.casecmp(Api.config.SECURE_SCHEME).zero?
    end

    def body_data
      raw = @routing.body.read
      raw.empty? ? {} : JSON.parse(raw, symbolize_names: true)
    end

    def authenticated_token
      header = @routing.env['HTTP_AUTHORIZATION']
      return nil unless header

      scheme, token = header.split(' ', 2)
      return nil unless scheme&.casecmp('Bearer')&.zero? && token

      AuthToken.load(token)
    end

    def authenticated_account
      authenticated_token&.payload
    end

    # token.scope is the serialized string stored in the bearer token.
    # AuthScope is the parsed object policies use for can_read?/can_write?.
    def auth_scope
      token = authenticated_token
      return nil unless token

      AuthScope.new(token.scope)
    end
  end
end
