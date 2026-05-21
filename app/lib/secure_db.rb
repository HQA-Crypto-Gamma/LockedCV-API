# frozen_string_literal: true

require_relative 'securable'

module LockedCV
  # Encrypt and decrypt values stored in the database.
  class SecureDB
    extend Securable

    NoDbKeyError = Securable::NoKeyError
    NoHashKeyError = Securable::NoHashKeyError

    def self.setup(base_key, hash_key)
      setup_secret_key(base_key)
      setup_hash_key(hash_key)
    end

    def self.encrypt(plaintext)
      base_encrypt(plaintext)
    end

    def self.decrypt(ciphertext64)
      base_decrypt(ciphertext64)
    end

    # Keyed hash for deterministic lookup on encrypted columns
    def self.hash(plaintext)
      base_hash(plaintext)
    end
  end
end
