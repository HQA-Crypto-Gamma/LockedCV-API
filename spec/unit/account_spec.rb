# frozen_string_literal: true

require_relative '../spec_helper'

describe LockedCV::Account do
  include LockedCV::SpecHelpers

  before do
    reset_database!
  end

  it 'HAPPY: creates account with password and stores in database' do
    payload = DATA[:accounts].first.transform_keys(&:to_sym)
    account = LockedCV::Account.create(payload)

    _(account.id).wont_be_nil
    _(account.password?('ada-secret')).must_equal true

    stored = db[:accounts].where(id: account.id).first
    _(stored[:password_digest]).wont_be_nil
    _(stored[:password_digest]).wont_include 'ada-secret'
  end

  it 'HAPPY: retrieves account and verifies password works' do
    payload = DATA[:accounts].first.transform_keys(&:to_sym)
    account = LockedCV::Account.create(payload)

    retrieved = LockedCV::Account[account.id]
    _(retrieved.password?('ada-secret')).must_equal true
    _(retrieved.password?('wrong-password')).must_equal false
  end

  it 'SAD: cannot save account without password' do
    payload = DATA[:accounts].first.transform_keys(&:to_sym)
    payload_no_pwd = payload.except(:password)
    account = LockedCV::Account.new(payload_no_pwd)

    _(account.password_digest).must_be_nil
  end

  it 'SECURITY: primary key id is protected from mass assignment' do
    payload = DATA[:accounts].first.transform_keys(&:to_sym)

    error = _(
      proc { LockedCV::Account.new(payload.merge(id: 'forced-id')) }
    ).must_raise Sequel::MassAssignmentRestriction

    _(error.message).must_include 'id'
  end

  it 'SECURITY: password digest never includes plaintext' do
    payload = DATA[:accounts].first.transform_keys(&:to_sym)
    account = LockedCV::Account.create(payload)

    stored = db[:accounts].where(id: account.id).first
    _(stored[:password_digest]).wont_include 'ada-secret'
    _(JSON.parse(stored[:password_digest])).must_be_kind_of Hash
  end

  it 'HAPPY: supports many-to-many system roles and role checks' do
    account = LockedCV::Account.create(DATA[:accounts].first.transform_keys(&:to_sym))
    admin_role = LockedCV::Role.create(name: 'admin')
    member_role = LockedCV::Role.create(name: 'member')

    account.add_system_role(admin_role)
    account.add_system_role(member_role)

    _(account.system_roles.map(&:name)).must_include 'admin'
    _(account.system_roles.map(&:name)).must_include 'member'
    _(account.admin?).must_equal true
    _(account.member?).must_equal true
    _(account.system_role?('viewer_full')).must_equal false
  end
end
