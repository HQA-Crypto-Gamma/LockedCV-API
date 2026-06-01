# frozen_string_literal: true

require_relative '../spec_helper'

describe LockedCV::AuthScope do
  it 'SECURITY: gives full read and write access by default' do
    scope = LockedCV::AuthScope.new

    _(scope.can_read?('*')).must_equal true
    _(scope.can_write?('*')).must_equal true
    _(scope.can_read?('accounts')).must_equal true
    _(scope.can_write?('attachments')).must_equal true
  end

  it 'SECURITY: supports read-only wildcard scopes' do
    scope = LockedCV::AuthScope.new(LockedCV::AuthScope::READ_ONLY)

    _(scope.can_read?('accounts')).must_equal true
    _(scope.can_read?('attachments')).must_equal true
    _(scope.can_write?('accounts')).must_equal false
    _(scope.can_write?('attachments')).must_equal false
  end

  it 'SECURITY: supports resource-specific read scopes' do
    scope = LockedCV::AuthScope.new('attachments:read')

    _(scope.can_read?('*')).must_equal false
    _(scope.can_write?('*')).must_equal false
    _(scope.can_read?('attachments')).must_equal true
    _(scope.can_write?('attachments')).must_equal false
    _(scope.can_read?('accounts')).must_equal false
  end

  it 'SECURITY: supports multiple resource scopes' do
    scope = LockedCV::AuthScope.new('accounts:read attachments:write')

    _(scope.can_read?('accounts')).must_equal true
    _(scope.can_write?('accounts')).must_equal false
    _(scope.can_read?('attachments')).must_equal true
    _(scope.can_write?('attachments')).must_equal true
  end

  it 'SECURITY: treats write scopes as readable' do
    scope = LockedCV::AuthScope.new('sensitive_data:write')

    _(scope.can_read?('sensitive_data')).must_equal true
    _(scope.can_write?('sensitive_data')).must_equal true
  end

  it 'SECURITY: preserves the original scope string' do
    _(LockedCV::AuthScope.new.to_s).must_equal LockedCV::AuthScope::FULL
    _(LockedCV::AuthScope.new(LockedCV::AuthScope::READ_ONLY).to_s)
      .must_equal LockedCV::AuthScope::READ_ONLY
  end
end
