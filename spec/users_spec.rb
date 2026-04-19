# frozen_string_literal: true

require_relative 'spec_helper'

describe 'User Endpoints' do
  include Rack::Test::Methods
  include LockedCV::SpecHelpers

  def app
    LockedCV::Api
  end

  before do
    reset_database!
  end

  describe 'POST /api/v1/users' do
    it 'HAPPY: creates a user' do
      payload = DATA[:users].last.transform_keys(&:to_sym)

      post '/api/v1/users', payload.to_json, req_header

      _(last_response.status).must_equal 201
      _(last_response.headers['Content-Type']).must_include 'application/json'
      _(json_body['message']).must_equal 'User saved'
      _(json_body.dig('data', 'data', 'attributes', 'phone_number')).must_equal payload[:phone_number]
    end
  end

  describe 'GET /api/v1/users/:id' do
    it 'HAPPY: gets a single user' do
      user = LockedCV::User.create(DATA[:users].first.transform_keys(&:to_sym))

      get "/api/v1/users/#{user.id}"

      _(last_response.status).must_equal 200
      _(last_response.headers['Content-Type']).must_include 'application/json'
      _(json_body.dig('data', 'type')).must_equal 'user'
      _(json_body.dig('data', 'attributes', 'id')).must_equal user.id
    end

    it 'SAD: returns 404 for missing user' do
      get '/api/v1/users/999999'

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'User not found')
    end
  end
end
