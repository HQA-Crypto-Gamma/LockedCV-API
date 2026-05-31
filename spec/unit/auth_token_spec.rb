# frozen_string_literal: true

require_relative '../spec_helper'

describe LockedCV::AuthToken do
  it 'SECURITY: creates an encrypted token that does not expose payload text' do
    payload = { 'account_id' => 'account-123', 'scope' => 'auth' }

    token = LockedCV::AuthToken.new(payload).to_s

    _(token).wont_include payload['account_id']
    _(token).wont_include payload['scope']
  end

  it 'SECURITY: loads token payload' do
    payload = { 'account_id' => 'account-123', 'roles' => ['member'] }
    token = LockedCV::AuthToken.new(payload).to_s

    loaded = LockedCV::AuthToken.load(token)

    _(loaded.payload).must_equal payload
  end

  it 'SECURITY: defaults new tokens to full authorization scope' do
    payload = { 'account_id' => 'account-123' }

    token = LockedCV::AuthToken.new(payload).to_s

    _(LockedCV::AuthToken.load(token).scope).must_equal LockedCV::AuthScope::FULL
  end

  it 'SECURITY: round-trips explicit read-only authorization scope' do
    payload = { 'account_id' => 'account-123' }
    scope = LockedCV::AuthScope.new(LockedCV::AuthScope::READ_ONLY)

    token = LockedCV::AuthToken.new(payload, scope:).to_s

    _(LockedCV::AuthToken.load(token).scope).must_equal LockedCV::AuthScope::READ_ONLY
  end

  it 'SECURITY: identifies fresh tokens' do
    token = LockedCV::AuthToken.new({ 'account_id' => 'account-123' })

    _(token.fresh?).must_equal true
  end

  it 'SECURITY: rejects expired token payload access' do
    token = LockedCV::AuthToken.new({ 'account_id' => 'account-123' }, -1).to_s
    loaded = LockedCV::AuthToken.load(token)

    _ { loaded.payload }.must_raise LockedCV::AuthToken::ExpiredTokenError
  end

  it 'SECURITY: rejects expired token scope access' do
    token = LockedCV::AuthToken.new({ 'account_id' => 'account-123' }, -1).to_s
    loaded = LockedCV::AuthToken.load(token)

    _ { loaded.scope }.must_raise LockedCV::AuthToken::ExpiredTokenError
  end

  it 'SECURITY: rejects invalid tokens' do
    _ { LockedCV::AuthToken.load('not-a-real-token') }
      .must_raise LockedCV::AuthToken::InvalidTokenError
  end

  it 'SECURITY: rejects tampered tokens' do
    token = LockedCV::AuthToken.new({ 'account_id' => 'account-123' }).to_s

    _ { LockedCV::AuthToken.load("#{token}tampered") }
      .must_raise LockedCV::AuthToken::InvalidTokenError
  end

  it 'SECURITY: generates setup-compatible keys' do
    key = LockedCV::AuthToken.generate_key

    LockedCV::AuthToken.setup(key)
    token = LockedCV::AuthToken.new({ 'account_id' => 'account-123' }).to_s

    _(LockedCV::AuthToken.load(token).payload).must_equal('account_id' => 'account-123')
  end
end
