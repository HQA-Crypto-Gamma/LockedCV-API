# frozen_string_literal: true

require 'cgi'
require_relative '../spec_helper'

describe 'Account Endpoints' do
  include Rack::Test::Methods
  include LockedCV::SpecHelpers

  def app
    LockedCV::Api
  end

  before do
    reset_database!
  end

  describe 'POST /api/v1/accounts/registration/check' do
    it 'HAPPY: returns available for unused username and email' do
      payload = {
        username: 'new-user',
        email: 'new-user@example.com'
      }

      post '/api/v1/accounts/registration/check', signed_body(payload), req_header

      _(last_response.status).must_equal 200
      _(json_body).must_equal('available' => true)
    end

    it 'SECURITY: rejects unsigned registration availability checks' do
      payload = {
        username: 'new-user',
        email: 'new-user@example.com'
      }

      post '/api/v1/accounts/registration/check', payload.to_json, req_header

      _(last_response.status).must_equal 403
      _(json_body).must_equal('message' => 'Must sign request')
    end

    it 'SAD: returns 400 for registered email' do
      account = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].first.transform_keys(&:to_sym)
      )
      payload = {
        username: 'new-user',
        email: account.email
      }

      post '/api/v1/accounts/registration/check', signed_body(payload), req_header

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Email already registered')
    end

    it 'SAD: returns 400 for registered username' do
      account = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].first.transform_keys(&:to_sym)
      )
      payload = {
        username: account.username,
        email: 'new-user@example.com'
      }

      post '/api/v1/accounts/registration/check', signed_body(payload), req_header

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Username already taken')
    end

    it 'SAD: returns 400 for missing email' do
      payload = {
        username: 'new-user',
        email: ''
      }

      post '/api/v1/accounts/registration/check', signed_body(payload), req_header

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Email is required')
    end

    it 'SAD: returns 400 for missing username' do
      payload = {
        username: '',
        email: 'new-user@example.com'
      }

      post '/api/v1/accounts/registration/check', signed_body(payload), req_header

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Username is required')
    end

    it 'SAD: trims registration values before checking availability' do
      account = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].first.transform_keys(&:to_sym)
      )
      payload = {
        username: "  #{account.username}  ",
        email: "  #{account.email}  "
      }

      post '/api/v1/accounts/registration/check', signed_body(payload), req_header

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Email already registered')
    end
  end

  describe 'POST /api/v1/accounts' do
    it 'HAPPY: creates an account' do
      payload = DATA[:accounts].last.transform_keys(&:to_sym)

      post '/api/v1/accounts', signed_body(payload), req_header

      _(last_response.status).must_equal 201
      _(last_response.headers['Content-Type']).must_include 'application/json'
      _(json_body['message']).must_equal 'Account saved'
      _(json_body.dig('data', 'data', 'attributes', 'email')).must_equal payload[:email]
      _(json_body.dig('data', 'data', 'attributes').keys).wont_include 'password'
      _(json_body.dig('data', 'data', 'attributes').keys).wont_include 'password_digest'
    end

    it 'SECURITY: rejects unsigned account creation requests' do
      payload = DATA[:accounts].last.transform_keys(&:to_sym)

      post '/api/v1/accounts', payload.to_json, req_header

      _(last_response.status).must_equal 403
      _(json_body).must_equal('message' => 'Must sign request')
    end

    it 'HAPPY: creates an account with optional personal data' do
      payload = DATA[:accounts].last.transform_keys(&:to_sym).merge(
        first_name: 'Alan',
        last_name: 'Turing',
        birthday: '1912-06-23',
        address: 'Manchester',
        identification_numbers: 'NINO-123'
      )

      post '/api/v1/accounts', signed_body(payload), req_header

      attributes = json_body.dig('data', 'data', 'attributes')

      _(last_response.status).must_equal 201
      _(attributes['first_name']).must_equal payload[:first_name]
      _(attributes['last_name']).must_equal payload[:last_name]
      _(attributes['birthday']).must_equal payload[:birthday]
      _(attributes['address']).must_equal payload[:address]
      _(attributes['identification_numbers']).must_equal payload[:identification_numbers]
      _(attributes.keys).wont_include 'first_name_secure'
      _(attributes.keys).wont_include 'identification_numbers_secure'
    end

    it 'SECURITY: returns 400 and does not create account on mass assignment' do
      payload = DATA[:accounts].last.merge('id' => 'forced-id')
      before_count = LockedCV::Account.count

      capture_app_logs do |logs|
        post '/api/v1/accounts', signed_body(payload), req_header

        _(last_response.status).must_equal 400
        _(json_body).must_equal('message' => 'Illegal attributes')
        _(logs.string).must_include 'MASS_ASSIGNMENT_ATTEMPT'
        _(logs.string).must_include 'keys=[:username, :email, :phone_number, :password, :id]'
        _(logs.string).wont_include payload['email']
      end

      _(LockedCV::Account.count).must_equal before_count
      _(LockedCV::Account.first(id: 'forced-id')).must_be_nil
    end

    it 'SAD: logs unknown errors for unexpected failures' do
      invalid_json = '{"first_name":"Ada"'

      capture_app_logs do |logs|
        post '/api/v1/accounts', invalid_json, req_header

        _(last_response.status).must_equal 500
        _(json_body).must_equal('message' => 'Database error')
        _(logs.string).must_include 'UNKNOWN ERROR:'
        _(logs.string).must_include "expected ',' or '}' after object value"
      end
    end
  end

  describe 'GET /api/v1/account' do
    it 'HAPPY: gets the current account from bearer token' do
      account = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].first.transform_keys(&:to_sym)
      )

      get '/api/v1/account', {}, auth_header(account)

      _(last_response.status).must_equal 200
      _(last_response.headers['Content-Type']).must_include 'application/json'
      _(json_body.dig('data', 'type')).must_equal 'account'
      _(json_body.dig('data', 'attributes', 'id')).must_equal account.id
      _(json_body.dig('data', 'attributes').keys).wont_include 'password'
      _(json_body.dig('data', 'attributes').keys).wont_include 'password_digest'
    end

    it 'HAPPY: allows current account reads from read-only tokens' do
      account = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].first.transform_keys(&:to_sym)
      )
      read_only = LockedCV::AuthScope.new(LockedCV::AuthScope::READ_ONLY)

      get '/api/v1/account', {}, auth_header(account, scope: read_only)

      _(last_response.status).must_equal 200
      _(json_body.dig('data', 'attributes', 'id')).must_equal account.id
    end

    it 'SECURITY: returns 401 without bearer token' do
      get '/api/v1/account'

      _(last_response.status).must_equal 401
      _(json_body).must_equal('message' => 'Missing authorization token')
    end

    it 'SECURITY: returns 401 for invalid bearer token' do
      get '/api/v1/account', {}, { 'HTTP_AUTHORIZATION' => 'Bearer invalid-token' }

      _(last_response.status).must_equal 401
      _(json_body).must_equal('message' => 'Invalid authorization token')
    end
  end

  describe 'PUT /api/v1/account' do
    it 'HAPPY: updates current account profile fields' do
      account = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].first.transform_keys(&:to_sym)
      )
      payload = {
        email: 'ada.updated@example.com',
        phone_number: '0912-999-001',
        first_name: 'Ada',
        last_name: 'Byron',
        birthday: '1815-12-10',
        address: 'London',
        identification_numbers: 'ID-999'
      }

      put '/api/v1/account', payload.to_json, auth_req_header(account)

      attributes = json_body.dig('data', 'data', 'attributes')

      _(last_response.status).must_equal 200
      _(json_body['message']).must_equal 'Account updated'
      _(attributes['email']).must_equal payload[:email]
      _(attributes['first_name']).must_equal payload[:first_name]
      _(attributes['identification_numbers']).must_equal payload[:identification_numbers]
      _(attributes.keys).wont_include 'email_secure'
    end

    it 'SECURITY: rejects profile updates from read-only tokens' do
      account = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].first.transform_keys(&:to_sym)
      )
      read_only = LockedCV::AuthScope.new(LockedCV::AuthScope::READ_ONLY)

      put '/api/v1/account', { first_name: 'Ada' }.to_json, auth_req_header(account, scope: read_only)

      _(last_response.status).must_equal 403
      _(json_body).must_equal('message' => 'Read-only tokens cannot update accounts')
    end

    it 'SECURITY: returns 401 without bearer token' do
      put '/api/v1/account', { first_name: 'Ada' }.to_json, req_header

      _(last_response.status).must_equal 401
      _(json_body).must_equal('message' => 'Missing authorization token')
    end
  end

  describe 'GET /api/v1/accounts/:username' do
    before do
      @admin_role = LockedCV::Role.create(name: 'admin')
      @admin = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].first.transform_keys(&:to_sym)
      )
      @target = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].last.transform_keys(&:to_sym)
      )
      LockedCV::SetSystemRoleService.call(account: @admin, role_name: @admin_role.name)
    end

    it 'HAPPY: returns account details with a read-only API token for self' do
      get "/api/v1/accounts/#{@target.username}", nil, auth_header(@target)

      _(last_response.status).must_equal 200
      data = json_body['data']
      account = data.dig('attributes', 'account')
      api_token = data.dig('attributes', 'auth_token')
      loaded_token = LockedCV::AuthToken.load(api_token)

      _(data['type']).must_equal 'authorized_account'
      _(account.dig('data', 'attributes', 'id')).must_equal @target.id
      _(account.dig('data', 'attributes', 'username')).must_equal @target.username
      _(loaded_token.scope).must_equal LockedCV::AuthScope::READ_ONLY
      _(loaded_token.payload['account_id']).must_equal @target.id
    end

    it 'HAPPY: lets admins request a read-only API token for another account' do
      get "/api/v1/accounts/#{@target.username}", nil, auth_header(@admin)

      _(last_response.status).must_equal 200
      api_token = json_body.dig('data', 'attributes', 'auth_token')

      _(LockedCV::AuthToken.load(api_token).scope).must_equal LockedCV::AuthScope::READ_ONLY
      _(LockedCV::AuthToken.load(api_token).payload['account_id']).must_equal @target.id
    end

    it 'SECURITY: hides account details from unrelated members' do
      get "/api/v1/accounts/#{@admin.username}", nil, auth_header(@target)

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Account not found')
    end

    it 'SECURITY: requires a bearer token' do
      get "/api/v1/accounts/#{@target.username}"

      _(last_response.status).must_equal 401
      _(json_body).must_equal('message' => 'Missing authorization token')
    end
  end

  describe 'DELETE /api/v1/accounts/:id' do
    before do
      @admin_role = LockedCV::Role.create(name: 'admin')
      @admin = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].first.transform_keys(&:to_sym)
      )
      @target = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].last.transform_keys(&:to_sym)
      )
      @admin.add_system_role(@admin_role)
    end

    it 'HAPPY: admin deletes an account' do
      delete(
        "/api/v1/accounts/#{@target.id}",
        nil,
        auth_header(@admin)
      )

      _(last_response.status).must_equal 200
      _(json_body).must_equal('message' => 'Account deleted')
      _(LockedCV::Account.first(id: @target.id)).must_be_nil
    end

    it 'HAPPY: deletes dependent attachments and sensitive data' do
      attachment = LockedCV::CreateAttachmentService.call(
        account_id: @target.id,
        attachment_data: {
          attachment_name: 'target-resume.pdf',
          route: 'target/target-resume.pdf'
        }
      )
      sensitive_data = LockedCV::CreateSensitiveDataService.call(
        account_id: @target.id,
        attachment_id: attachment.id,
        sensitive_data: {
          first_name: 'Alan',
          last_name: 'Turing',
          phone_number: '0912-000-002',
          birthday: '1912-06-23',
          email: 'alan@example.com',
          address: 'Manchester',
          identification_numbers: 'NINO-123'
        }
      )

      delete(
        "/api/v1/accounts/#{@target.id}",
        nil,
        auth_header(@admin)
      )

      _(last_response.status).must_equal 200
      _(LockedCV::Attachment.first(id: attachment.id)).must_be_nil
      _(LockedCV::SensitiveData.first(id: sensitive_data.id)).must_be_nil
    end

    it 'SAD: non-admin cannot delete an account' do
      non_admin = LockedCV::CreateAccountService.call(
        account_data: {
          username: 'grace-hopper',
          email: 'grace@example.com',
          phone_number: '0912-000-003',
          password: 'grace-secret'
        }
      )

      delete(
        "/api/v1/accounts/#{@target.id}",
        nil,
        auth_header(non_admin)
      )

      _(last_response.status).must_equal 403
      _(json_body).must_equal('message' => 'Only admins can delete accounts')
      _(LockedCV::Account.first(id: @target.id)).wont_be_nil
    end

    it 'SAD: admin cannot delete their own account' do
      delete(
        "/api/v1/accounts/#{@admin.id}",
        nil,
        auth_header(@admin)
      )

      _(last_response.status).must_equal 403
      _(json_body).must_equal('message' => 'Admins cannot delete their own account')
      _(LockedCV::Account.first(id: @admin.id)).wont_be_nil
    end

    it 'SAD: returns 404 for missing account' do
      delete(
        '/api/v1/accounts/missing-account',
        nil,
        auth_header(@admin)
      )

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Account not found')
    end

    it 'SECURITY: missing bearer token returns 401' do
      delete "/api/v1/accounts/#{@target.id}"

      _(last_response.status).must_equal 401
      _(json_body).must_equal('message' => 'Missing authorization token')
      _(LockedCV::Account.first(id: @target.id)).wont_be_nil
    end
  end

  describe 'GET /api/v1/accounts' do
    before do
      @admin_role = LockedCV::Role.create(name: 'admin')
      @admin = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].first.transform_keys(&:to_sym)
      )
      @target = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].last.transform_keys(&:to_sym)
      )
      LockedCV::SetSystemRoleService.call(account: @admin, role_name: @admin_role.name)
    end

    it 'HAPPY: admin lists accounts through policy scope' do
      get '/api/v1/accounts', nil, auth_header(@admin)

      _(last_response.status).must_equal 200
      usernames = json_body['data'].map { |account| account.dig('attributes', 'username') }
      _(usernames).must_equal [@admin.username, @target.username].sort
    end

    it 'SAD: non-admin cannot list accounts' do
      get '/api/v1/accounts', nil, auth_header(@target)

      _(last_response.status).must_equal 403
      _(json_body).must_equal('message' => 'Only admins can list accounts')
    end
  end
end
