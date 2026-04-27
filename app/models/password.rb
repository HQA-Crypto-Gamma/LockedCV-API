# frozen_string_literal: true

require 'base64'
require 'json'
require_relative '../lib/key_stretch'

module LockedCV
  # Value object for salted and stretched password digests
  class Password
    extend KeyStretch

    def initialize(salt, digest)
      @salt = salt
      @digest = digest
    end

    def correct?(password)
      new_digest = Password.password_hash(@salt, password)
      @digest == new_digest
    end

    def to_json(options = {})
      JSON(
        {
          salt: Base64.strict_encode64(@salt),
          hash: Base64.strict_encode64(@digest)
        },
        options
      )
    end

    alias to_s to_json

    def self.digest(password)
      raise ArgumentError, 'Password must be a non-empty String' unless password.is_a?(String) && !password.empty?

      salt = new_salt
      hash = password_hash(salt, password)
      new(salt, hash)
    end

    def self.from_digest(digest)
      digested = JSON.parse(digest)
      salt = Base64.strict_decode64(digested['salt'])
      hash = Base64.strict_decode64(digested['hash'])
      new(salt, hash)
    end
  end
end
