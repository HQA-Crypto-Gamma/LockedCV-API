# frozen_string_literal: true

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
      _(json_body.dig('data', 'data', 'attributes', 'phone_number')).must_equal payload[:phone_number]
    end

    it 'SECURITY: returns 400 and does not create account on mass assignment' do
      payload = DATA[:accounts].last.merge('id' => 'forced-id')
      before_count = LockedCV::Account.count

      capture_app_logs do |logs|
        post '/api/v1/accounts', payload.to_json, req_header

        _(last_response.status).must_equal 400
        _(json_body).must_equal('message' => 'Illegal attributes')
        _(logs.string).must_include 'MASS_ASSIGNMENT_ATTEMPT'
        _(logs.string).must_include 'keys=["first_name", "last_name", "phone_number", "id"]'
        _(logs.string).wont_include payload['phone_number']
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
      account = LockedCV::Account.create(DATA[:accounts].first.transform_keys(&:to_sym))

      get "/api/v1/accounts/#{account.id}"

      _(last_response.status).must_equal 200
      _(last_response.headers['Content-Type']).must_include 'application/json'
      _(json_body.dig('data', 'type')).must_equal 'account'
      _(json_body.dig('data', 'attributes', 'id')).must_equal account.id
    end

    it 'SAD: returns 404 for missing account' do
      get '/api/v1/accounts/999999'

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Account not found')
    end
  end
end
