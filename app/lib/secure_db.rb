# frozen_string_literal: true

require 'base64'
require 'rbnacl'

module LockedCV
  # Encrypt and Decrypt from Database
  class SecureDB
    class NoDbKeyError < StandardError; end
    class NoHashKeyError < StandardError; end

    # Generate key for Rake tasks (typically not called at runtime)
    def self.generate_key
      key = RbNaCl::Random.random_bytes(RbNaCl::SecretBox.key_bytes)
      Base64.strict_encode64 key
    end

    def self.setup(base_key, hash_key)
      raise NoDbKeyError unless base_key
      raise NoHashKeyError unless hash_key

      @key = Base64.strict_decode64(base_key)
      @hash_key = Base64.strict_decode64(hash_key)
    end

    # Encrypt or else return nil if data is nil
    def self.encrypt(plaintext)
      return nil unless plaintext

      simple_box = RbNaCl::SimpleBox.from_secret_key(@key)
      ciphertext = simple_box.encrypt(plaintext)
      Base64.strict_encode64(ciphertext)
    end

    # Decrypt or else return nil if database value is nil already
    def self.decrypt(ciphertext64)
      return nil unless ciphertext64

      ciphertext = Base64.strict_decode64(ciphertext64)
      simple_box = RbNaCl::SimpleBox.from_secret_key(@key)
      simple_box.decrypt(ciphertext).force_encoding(Encoding::UTF_8)
    end

    # Keyed hash for deterministic lookup on encrypted columns
    def self.hash(plaintext)
      return nil unless plaintext

      digest = RbNaCl::HMAC::SHA256.auth(@hash_key, plaintext)
      Base64.strict_encode64(digest)
    end
  end
end
