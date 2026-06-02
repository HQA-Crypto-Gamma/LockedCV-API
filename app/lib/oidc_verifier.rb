# frozen_string_literal: true

require 'jwt'

module LockedCV
  # Verifies an OpenID Connect id_token using a provider JWKS document.
  class OidcVerifier
    class VerificationError < StandardError; end

    def initialize(audience:, allowed_issuers:)
      @audience = audience
      @allowed_issuers = allowed_issuers
    end

    def verify(id_token, jwks:)
      claims, = JWT.decode(id_token, signing_key(id_token, jwks), true, decode_options)
      validate_claims!(claims)
      claims
    rescue JWT::DecodeError => e
      raise VerificationError, "Invalid id_token: #{e.message}"
    end

    private

    def decode_options
      { algorithms: ['RS256'], verify_expiration: true }
    end

    def signing_key(id_token, jwks)
      token_kid = key_id(id_token)
      jwk = jwks_keys(jwks).find { |key| key['kid'] == token_kid || key[:kid] == token_kid }
      raise VerificationError, 'No matching JWKS key' unless jwk

      JWT::JWK.import(jwk).verify_key
    end

    def jwks_keys(jwks)
      return [] unless jwks.respond_to?(:fetch)

      jwks.fetch('keys', jwks.fetch(:keys, []))
    end

    def key_id(id_token)
      _payload, header = JWT.decode(id_token, nil, false)
      header.fetch('kid')
    rescue KeyError
      raise VerificationError, 'Missing token key id'
    end

    def validate_claims!(claims)
      raise VerificationError, 'Invalid token issuer' unless @allowed_issuers.include?(claims['iss'])
      raise VerificationError, 'Invalid token audience' unless claims['aud'] == @audience
    end
  end
end
