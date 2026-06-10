# frozen_string_literal: true

require 'json'
require_relative 'securable'
require_relative 'auth_scope'

module LockedCV
  # Time-limited encrypted token carrying an authorization payload and scope.
  class AuthToken
    extend Securable

    class ExpiredTokenError < StandardError; end
    class InvalidTokenError < StandardError; end

    ONE_HOUR = 60 * 60
    ONE_DAY = ONE_HOUR * 24
    ONE_WEEK = ONE_DAY * 7

    def self.setup(base_key)
      setup_secret_key(base_key)
    end

    def self.tokenize(message)
      base_encrypt(JSON.generate(message))
    end

    def self.detokenize(ciphertext64)
      JSON.parse(base_decrypt(ciphertext64))
    rescue StandardError
      raise InvalidTokenError
    end

    def self.load(token)
      contents = detokenize(token)
      instance = allocate
      instance.instance_variable_set(:@token, token)
      instance.instance_variable_set(:@payload, contents['payload'])
      instance.instance_variable_set(:@scope, contents['scope'])
      instance.instance_variable_set(:@expiration, contents['exp'])
      instance
    end

    def initialize(payload, expiration = ONE_WEEK, scope: AuthScope.new)
      @payload = payload
      @scope = scope
      @expiration = (Time.now + expiration).to_i
      @token = self.class.tokenize(
        'payload' => @payload, 'scope' => @scope.to_s, 'exp' => @expiration
      )
    end

    def payload
      raise ExpiredTokenError if expired?

      @payload
    end

    def scope
      raise ExpiredTokenError if expired?
      raise InvalidTokenError unless @scope.is_a?(String)

      @scope
    end

    def expired?
      raise InvalidTokenError unless @expiration.is_a?(Integer)

      Time.now.to_i > @expiration
    end

    def fresh?
      !expired?
    end

    def to_s
      @token
    end
  end
end
