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
    @account_data = DATA[:accounts].first.transform_keys(&:to_sym)
    @account = LockedCV::CreateAccountService.call(account_data: @account_data)
  end

  after do
    WebMock.reset!
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
    auth_token = json_body.dig('data', 'attributes', 'auth_token')
    payload = LockedCV::AuthToken.load(auth_token).payload
    _(payload['account_id']).must_equal @account.id
    _(payload['username']).must_equal @account.username
    _(payload['email']).must_equal @account.email
    _(json_body.dig('data', 'attributes').keys).wont_include 'password'
    _(json_body.dig('data', 'attributes').keys).wont_include 'password_digest'
  end

  it 'SAD: rejects invalid password' do
    credentials = {
      username: @account_data[:username],
      password: 'not-the-password'
    }

    capture_app_logs do |logs|
      post '/api/v1/auth/authenticate', credentials.to_json, req_header

      _(logs.string).must_include 'Authentication failed: invalid credentials'
    end

    _(last_response.status).must_equal 403
    _(json_body).must_equal('message' => 'Invalid credentials')
  end

  it 'SAD: rejects unknown username' do
    credentials = {
      username: 'missing-account',
      password: @account_data[:password]
    }

    capture_app_logs do |logs|
      post '/api/v1/auth/authenticate', credentials.to_json, req_header

      _(logs.string).must_include 'Authentication failed: invalid credentials'
    end

    _(last_response.status).must_equal 403
    _(json_body).must_equal('message' => 'Invalid credentials')
  end

  describe 'POST /api/v1/auth/register' do
    before do
      reset_database!
      @registration = {
        username: 'grace-hopper',
        email: 'grace@example.com',
        verification_url: 'https://lockedcv.example.test/auth/register/token'
      }
      @mailgun_url = "https://api.mailgun.net/v3/#{ENV.fetch('MAILGUN_DOMAIN').strip}/messages"
    end

    it 'HAPPY: sends registration verification email' do
      WebMock.stub_request(:post, @mailgun_url)
             .with do |request|
               form = URI.decode_www_form(request.body).to_h
               request.headers['Authorization'].to_s.start_with?('Basic ') &&
                 form['to'] == @registration[:email] &&
                 form['from'].include?(ENV.fetch('MAILGUN_FROM_EMAIL')) &&
                 form['subject'] == 'LockedCV Registration Verification' &&
                 form['html'].include?(@registration[:verification_url])
             end
             .to_return(status: 200, body: { id: 'message-id' }.to_json)

      post '/api/v1/auth/register', @registration.to_json, req_header

      _(last_response.status).must_equal 202
      _(json_body).must_equal('message' => 'Verification email sent')
      _(LockedCV::Account.count).must_equal 0
    end

    it 'SAD: rejects missing verification URL' do
      post '/api/v1/auth/register', @registration.merge(verification_url: '').to_json, req_header

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Verification URL is required')
      assert_not_requested(:post, @mailgun_url)
    end

    it 'SAD: rejects missing email' do
      post '/api/v1/auth/register', @registration.merge(email: '').to_json, req_header

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Email is required')
      assert_not_requested(:post, @mailgun_url)
    end

    it 'SAD: rejects missing username' do
      post '/api/v1/auth/register', @registration.merge(username: '').to_json, req_header

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Username is required')
      assert_not_requested(:post, @mailgun_url)
    end

    it 'SAD: rejects registered email' do
      account = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].first.transform_keys(&:to_sym)
      )

      post '/api/v1/auth/register', @registration.merge(email: account.email).to_json, req_header

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Email already registered')
      assert_not_requested(:post, @mailgun_url)
    end

    it 'SAD: rejects taken username' do
      account = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].first.transform_keys(&:to_sym)
      )

      post '/api/v1/auth/register', @registration.merge(username: account.username).to_json, req_header

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Username already taken')
      assert_not_requested(:post, @mailgun_url)
    end

    it 'HAPPY: trims registration fields before sending verification email' do
      padded_registration = {
        username: '  grace-hopper  ',
        email: '  grace@example.com  ',
        verification_url: '  https://lockedcv.example.test/auth/register/token  '
      }

      WebMock.stub_request(:post, @mailgun_url)
             .with do |request|
               form = URI.decode_www_form(request.body).to_h
               form['to'] == @registration[:email] &&
                 form['html'].include?('Welcome to LockedCV, grace-hopper!') &&
                 form['html'].include?(@registration[:verification_url])
             end
             .to_return(status: 200, body: { id: 'message-id' }.to_json)

      post '/api/v1/auth/register', padded_registration.to_json, req_header

      _(last_response.status).must_equal 202
      _(json_body).must_equal('message' => 'Verification email sent')
      assert_requested(:post, @mailgun_url, times: 1)
      _(LockedCV::Account.count).must_equal 0
    end

    it 'SAD: returns 500 when Mailgun rejects the email' do
      WebMock.stub_request(:post, @mailgun_url)
             .to_return(status: 500, body: 'provider down')

      post '/api/v1/auth/register', @registration.to_json, req_header

      _(last_response.status).must_equal 500
      _(json_body).must_equal('message' => 'Could not send verification email')
      _(LockedCV::Account.count).must_equal 0
    end

    it 'SAD: returns 500 when Mailgun request fails' do
      WebMock.stub_request(:post, @mailgun_url)
             .to_raise(HTTP::Error.new('network down'))

      post '/api/v1/auth/register', @registration.to_json, req_header

      _(last_response.status).must_equal 500
      _(json_body).must_equal('message' => 'Could not send verification email')
      _(LockedCV::Account.count).must_equal 0
    end
  end

  describe 'POST /api/v1/auth/sso' do
    it 'HAPPY: authenticates a valid Google ID token and creates a member account' do
      reset_database!

      post '/api/v1/auth/sso',
           { provider: 'google', id_token: google_id_token, jwks: google_jwks }.to_json,
           req_header

      _(last_response.status).must_equal 200
      _(json_body.dig('data', 'type')).must_equal 'authenticated_account'
      attributes = json_body.dig('data', 'attributes')
      _(attributes['email']).must_equal 'google-user@example.com'
      _(attributes['username']).must_equal 'google-user'
      _(attributes['roles']).must_equal ['member']
      _(LockedCV::Account.count).must_equal 1
      _(LockedCV::AuthToken.load(attributes['auth_token']).scope).must_equal LockedCV::AuthScope::FULL
    end

    it 'HAPPY: uses the email local part rather than Google display name for SSO username' do
      reset_database!
      token = google_id_token(
        'email' => 'vick.fan@example.com',
        'name' => '王小明'
      )

      post '/api/v1/auth/sso',
           { provider: 'google', id_token: token, jwks: google_jwks }.to_json,
           req_header

      _(last_response.status).must_equal 200
      _(json_body.dig('data', 'attributes', 'username')).must_equal 'vick.fan'
    end

    it 'HAPPY: reuses an existing account with the same verified Google email' do
      token = google_id_token('email' => @account.email, 'name' => @account.username)

      post '/api/v1/auth/sso',
           { provider: 'google', id_token: token, jwks: google_jwks }.to_json,
           req_header

      _(last_response.status).must_equal 200
      _(json_body.dig('data', 'attributes', 'id')).must_equal @account.id
      _(LockedCV::Account.count).must_equal 1
    end

    it 'SAD: rejects missing SSO token data as a bad request' do
      post '/api/v1/auth/sso', { provider: 'google' }.to_json, req_header

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Invalid SSO request')
    end

    it 'SAD: rejects unsupported SSO provider' do
      post '/api/v1/auth/sso',
           { provider: 'github', id_token: google_id_token, jwks: google_jwks }.to_json,
           req_header

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Unsupported SSO provider')
    end

    it 'SAD: rejects invalid Google ID token claims' do
      post '/api/v1/auth/sso',
           { provider: 'google', id_token: google_id_token('aud' => 'wrong-client'), jwks: google_jwks }.to_json,
           req_header

      _(last_response.status).must_equal 401
      _(json_body).must_equal('message' => 'Invalid SSO token')
    end

    it 'SAD: rejects unverified Google email' do
      post '/api/v1/auth/sso',
           { provider: 'google', id_token: google_id_token('email_verified' => false), jwks: google_jwks }.to_json,
           req_header

      _(last_response.status).must_equal 401
      _(json_body).must_equal('message' => 'Invalid SSO token')
    end
  end
end
