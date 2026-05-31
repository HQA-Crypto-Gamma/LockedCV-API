# frozen_string_literal: true

module LockedCV
  # OAuth-style authorization scope carried inside an AuthToken.
  #
  # Scope strings are space-separated resource grants such as:
  #   "*:write"
  #   "*:read"
  #   "accounts:read attachments:write"
  #
  # The wildcard resource "*" matches every resource, and write implies read.
  # Policies should ask can_read?/can_write? for their resource before applying
  # ownership, system role, or resource role rules.
  class AuthScope
    ALL = '*'
    READ = 'read'
    WRITE = 'write'
    FULL = '*:write'
    READ_ONLY = '*:read'

    SEPARATOR = ' '
    DIVIDER = ':'

    def initialize(scopes = FULL)
      @scopes_str = scopes
      @scopes = {}
      scopes.split(SEPARATOR).each { |scope| add_scope(scope) }
    end

    def can_read?(resource)
      readable?(ALL) || readable?(resource)
    end

    def can_write?(resource)
      writeable?(ALL) || writeable?(resource)
    end

    def to_s
      @scopes_str
    end

    private

    def readable?(resource)
      writeable?(resource) || permission_granted?(resource, READ)
    end

    def writeable?(resource)
      permission_granted?(resource, WRITE)
    end

    def permission_granted?(resource, permission)
      @scopes[resource]&.include?(permission) || false
    end

    def add_scope(scope)
      resource, permission = scope.split(DIVIDER)
      @scopes[resource] ||= []
      @scopes[resource] << permission
    end
  end
end
