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

  describe 'POST /api/v1/accounts' do
    it 'HAPPY: creates an account' do
      payload = DATA[:accounts].last.transform_keys(&:to_sym)

      post '/api/v1/accounts', payload.to_json, req_header

      _(last_response.status).must_equal 201
      _(last_response.headers['Content-Type']).must_include 'application/json'
      _(json_body['message']).must_equal 'Account saved'
      _(json_body.dig('data', 'data', 'attributes', 'email')).must_equal payload[:email]
      _(json_body.dig('data', 'data', 'attributes').keys).wont_include 'password'
      _(json_body.dig('data', 'data', 'attributes').keys).wont_include 'password_digest'
    end

    it 'HAPPY: creates an account with optional personal data' do
      payload = DATA[:accounts].last.transform_keys(&:to_sym).merge(
        first_name: 'Alan',
        last_name: 'Turing',
        birthday: '1912-06-23',
        address: 'Manchester',
        identification_numbers: 'NINO-123'
      )

      post '/api/v1/accounts', payload.to_json, req_header

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
        post '/api/v1/accounts', payload.to_json, req_header

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

  describe 'GET /api/v1/accounts/:id' do
    it 'HAPPY: gets a single account' do
      account = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].first.transform_keys(&:to_sym)
      )

      get "/api/v1/accounts/#{account.id}"

      _(last_response.status).must_equal 200
      _(last_response.headers['Content-Type']).must_include 'application/json'
      _(json_body.dig('data', 'type')).must_equal 'account'
      _(json_body.dig('data', 'attributes', 'id')).must_equal account.id
      _(json_body.dig('data', 'attributes').keys).wont_include 'password'
      _(json_body.dig('data', 'attributes').keys).wont_include 'password_digest'
    end

    it 'SAD: returns 404 for missing account' do
      get '/api/v1/accounts/999999'

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Account not found')
    end

    it 'SECURITY: rejects SQL injection in account id' do
      account = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].first.transform_keys(&:to_sym)
      )
      injected_account_id = CGI.escape("#{account.id}' OR '1'='1")

      get "/api/v1/accounts/#{injected_account_id}"

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Account not found')
    end
  end

  describe 'PUT /api/v1/accounts/:id' do
    it 'HAPPY: updates editable account profile fields' do
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

      put "/api/v1/accounts/#{account.id}", payload.to_json, req_header

      attributes = json_body.dig('data', 'data', 'attributes')

      _(last_response.status).must_equal 200
      _(json_body['message']).must_equal 'Account updated'
      _(attributes['email']).must_equal payload[:email]
      _(attributes['first_name']).must_equal payload[:first_name]
      _(attributes['identification_numbers']).must_equal payload[:identification_numbers]
      _(attributes.keys).wont_include 'email_secure'
    end

    it 'SAD: returns 404 for missing account update' do
      put '/api/v1/accounts/missing-account', { first_name: 'Ada' }.to_json, req_header

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Account not found')
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
        { current_account_id: @admin.id }.to_json,
        req_header
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
        { current_account_id: @admin.id }.to_json,
        req_header
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
        { current_account_id: non_admin.id }.to_json,
        req_header
      )

      _(last_response.status).must_equal 403
      _(json_body).must_equal('message' => 'Only admins can delete accounts')
      _(LockedCV::Account.first(id: @target.id)).wont_be_nil
    end

    it 'SAD: admin cannot delete their own account' do
      delete(
        "/api/v1/accounts/#{@admin.id}",
        { current_account_id: @admin.id }.to_json,
        req_header
      )

      _(last_response.status).must_equal 403
      _(json_body).must_equal('message' => 'Admins cannot delete their own account')
      _(LockedCV::Account.first(id: @admin.id)).wont_be_nil
    end

    it 'SAD: returns 404 for missing account' do
      delete(
        '/api/v1/accounts/missing-account',
        { current_account_id: @admin.id }.to_json,
        req_header
      )

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Account not found')
    end

    it 'SECURITY: missing current_account_id returns 401' do
      delete "/api/v1/accounts/#{@target.id}", {}.to_json, req_header

      _(last_response.status).must_equal 401
      _(json_body).must_equal('message' => 'Missing current_account_id')
      _(LockedCV::Account.first(id: @target.id)).wont_be_nil
    end
  end
end
