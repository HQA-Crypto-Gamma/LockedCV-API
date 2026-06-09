# frozen_string_literal: true

require 'base64'
require 'json'
require 'rbnacl'

module LockedCV
  # Verifies Ed25519-signed request bodies from trusted client applications.
  module SignedRequest
    class VerificationError < StandardError; end
    class KeypairError < StandardError; end

    module_function

    def setup(verify_key64, signing_key64 = nil)
      @verify_key = Base64.strict_decode64(verify_key64)
      @signing_key = signing_key64 ? Base64.strict_decode64(signing_key64) : nil
    rescue StandardError => e
      raise KeypairError, e.message
    end

    def generate_keypair
      signing_key = RbNaCl::SigningKey.generate
      {
        signing_key: Base64.strict_encode64(signing_key.to_bytes),
        verify_key: Base64.strict_encode64(signing_key.verify_key.to_bytes)
      }
    end

    def parse(signed_request)
      data = value_at(signed_request, :data)
      signature = value_at(signed_request, :signature)

      verify(data, signature)
      data
    end

    def sign(message)
      raise KeypairError, 'SIGNING_KEY not configured' unless @signing_key

      signature = RbNaCl::SigningKey.new(@signing_key).sign(message.to_json)

      {
        data: message,
        signature: Base64.strict_encode64(signature)
      }
    end

    def verify(message, signature64)
      raise VerificationError, 'VERIFY_KEY not configured' unless @verify_key
      raise VerificationError, 'Missing signature' if signature64.to_s.empty?

      signature = Base64.strict_decode64(signature64)
      RbNaCl::VerifyKey.new(@verify_key).verify(signature, message.to_json)
      true
    rescue RbNaCl::BadSignatureError, ArgumentError
      raise VerificationError, 'Invalid signature'
    end

    def value_at(hash, key)
      hash.fetch(key.to_s) { hash.fetch(key) }
    rescue NoMethodError, KeyError
      raise VerificationError, "Missing #{key}"
    end
  end
end
