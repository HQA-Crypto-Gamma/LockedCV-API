# frozen_string_literal: true

module LockedCV
  # Google-specific ID token verifier.
  class GoogleIdToken
    ISSUERS = ['https://accounts.google.com', 'accounts.google.com'].freeze

    def self.verify(id_token, jwks:)
      OidcVerifier.new(
        audience: google_client_id,
        allowed_issuers: ISSUERS
      ).verify(id_token, jwks:)
    end

    def self.google_client_id
      return 'test-google-client-id' if Api.environment == :test

      Api.config.GOOGLE_CLIENT_ID
    end
    private_class_method :google_client_id
  end
end
