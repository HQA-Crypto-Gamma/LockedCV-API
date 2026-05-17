# frozen_string_literal: true

require 'base64'
require 'rbnacl'

module LockedCV
  # Shared crypto primitives for SecureDB and AuthToken.
  module Securable
    class NoKeyError < StandardError; end
    class NoHashKeyError < StandardError; end

    def generate_key
      key = RbNaCl::Random.random_bytes(RbNaCl::SecretBox.key_bytes)
      Base64.strict_encode64(key)
    end

    def setup_secret_key(secret_key)
      raise NoKeyError unless secret_key

      @key = Base64.strict_decode64(secret_key)
    end

    def setup_hash_key(hash_key)
      raise NoHashKeyError unless hash_key

      @hash_key = Base64.strict_decode64(hash_key)
    end

    def base_encrypt(plaintext)
      return nil unless plaintext

      simple_box = RbNaCl::SimpleBox.from_secret_key(@key)
      ciphertext = simple_box.encrypt(plaintext)
      Base64.strict_encode64(ciphertext)
    end

    def base_decrypt(ciphertext64)
      return nil unless ciphertext64

      ciphertext = Base64.strict_decode64(ciphertext64)
      simple_box = RbNaCl::SimpleBox.from_secret_key(@key)
      simple_box.decrypt(ciphertext).force_encoding(Encoding::UTF_8)
    end

    def base_hash(plaintext)
      return nil unless plaintext

      digest = RbNaCl::HMAC::SHA256.auth(@hash_key, plaintext)
      Base64.strict_encode64(digest)
    end
  end
end
