# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Change Password Endpoint' do
  include Rack::Test::Methods
  include LockedCV::SpecHelpers

  def app
    LockedCV::Api
  end

  before do
    reset_database!
    @account_data = DATA[:accounts].first.transform_keys(&:to_sym)
    @account = LockedCV::CreateAccountService.call(account_data: @account_data)
  end

  it 'HAPPY: changes an account password' do
    put "/api/v1/accounts/#{@account.id}/password", password_payload.to_json, req_header

    @account.refresh

    _(last_response.status).must_equal 200
    _(json_body).must_equal('message' => 'Password updated')
    _(@account.password?(@account_data[:password])).must_equal false
    _(@account.password?('new-secret')).must_equal true
  end

  it 'SECURITY: does not include password data in the response' do
    put "/api/v1/accounts/#{@account.id}/password", password_payload.to_json, req_header

    _(last_response.status).must_equal 200
    _(last_response.body).wont_include 'password_digest'
    _(last_response.body).wont_include 'new-secret'
  end

  it 'SAD: rejects an incorrect current password' do
    put "/api/v1/accounts/#{@account.id}/password",
        password_payload(current_password: 'wrong-secret').to_json,
        req_header

    @account.refresh

    _(last_response.status).must_equal 400
    _(json_body).must_equal('message' => 'Current password is incorrect')
    _(@account.password?(@account_data[:password])).must_equal true
    _(@account.password?('new-secret')).must_equal false
  end

  it 'SAD: rejects a blank new password' do
    put "/api/v1/accounts/#{@account.id}/password",
        password_payload(password: '').to_json,
        req_header

    _(last_response.status).must_equal 400
    _(json_body).must_equal('message' => 'Password is required')
  end

  it 'SAD: returns 404 for a missing account' do
    put '/api/v1/accounts/missing-account/password', password_payload.to_json, req_header

    _(last_response.status).must_equal 404
    _(json_body).must_equal('message' => 'Account not found')
  end

  def password_payload(overrides = {})
    {
      current_password: @account_data[:password],
      password: 'new-secret'
    }.merge(overrides)
  end
end
