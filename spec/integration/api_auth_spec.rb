# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Authentication Endpoint' do
  include Rack::Test::Methods
  include LockedCV::SpecHelpers

  def app
    LockedCV::Api
  end

  before do
    reset_database!
    @role = LockedCV::Role.create(name: 'member')
    @account_data = DATA[:accounts].first.transform_keys(&:to_sym)
    @account = LockedCV::CreateAccountService.call(account_data: @account_data)
    @account.add_system_role(@role)
  end

  it 'HAPPY: authenticates valid credentials' do
    credentials = {
      username: @account_data[:username],
      password: @account_data[:password]
    }

    post '/api/v1/auth/authenticate', credentials.to_json, req_header

    _(last_response.status).must_equal 200
    _(last_response.headers['Content-Type']).must_include 'application/json'
    _(json_body.dig('data', 'type')).must_equal 'authenticated_account'
    _(json_body.dig('data', 'attributes', 'id')).must_equal @account.id
    _(json_body.dig('data', 'attributes', 'username')).must_equal @account.username
    _(json_body.dig('data', 'attributes', 'email')).must_equal @account.email
    _(json_body.dig('data', 'attributes', 'roles')).must_equal ['member']
    _(json_body.dig('data', 'attributes').keys).wont_include 'password'
    _(json_body.dig('data', 'attributes').keys).wont_include 'password_digest'
  end

  it 'SAD: rejects invalid password' do
    credentials = {
      username: @account_data[:username],
      password: 'not-the-password'
    }

    assert_output(/invalid/i, '') do
      post '/api/v1/auth/authenticate', credentials.to_json, req_header
    end

    _(last_response.status).must_equal 403
    _(json_body).must_equal('message' => 'Invalid credentials')
  end

  it 'SAD: rejects unknown username' do
    credentials = {
      username: 'missing-account',
      password: @account_data[:password]
    }

    assert_output(/invalid/i, '') do
      post '/api/v1/auth/authenticate', credentials.to_json, req_header
    end

    _(last_response.status).must_equal 403
    _(json_body).must_equal('message' => 'Invalid credentials')
  end
end
