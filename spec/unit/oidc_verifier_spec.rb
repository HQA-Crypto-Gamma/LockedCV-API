# frozen_string_literal: true

require_relative '../spec_helper'

describe 'OIDC token verifier' do
  include LockedCV::SpecHelpers

  def verifier
    LockedCV::OidcVerifier.new(
      audience: 'test-google-client-id',
      allowed_issuers: LockedCV::GoogleIdToken::ISSUERS
    )
  end

  it 'HAPPY: verifies a valid Google ID token' do
    claims = verifier.verify(google_id_token, jwks: google_jwks)

    _(claims['email']).must_equal 'google-user@example.com'
    _(claims['iss']).must_equal 'https://accounts.google.com'
  end

  it 'SAD: rejects a token with the wrong audience' do
    _(
      proc { verifier.verify(google_id_token('aud' => 'wrong-client'), jwks: google_jwks) }
    ).must_raise LockedCV::OidcVerifier::VerificationError
  end

  it 'SAD: rejects a token with the wrong issuer' do
    _(
      proc { verifier.verify(google_id_token('iss' => 'https://evil.example'), jwks: google_jwks) }
    ).must_raise LockedCV::OidcVerifier::VerificationError
  end

  it 'SAD: rejects a token without a matching JWKS key' do
    _(
      proc { verifier.verify(google_id_token, jwks: { keys: [] }) }
    ).must_raise LockedCV::OidcVerifier::VerificationError
  end
end
