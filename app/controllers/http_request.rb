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

    def authenticated_account
      header = @routing.headers['AUTHORIZATION']
      return nil unless header

      scheme, token = header.split(' ', 2)
      return nil unless scheme&.casecmp('Bearer')&.zero? && token

      AuthToken.load(token).payload
    end
  end
end
