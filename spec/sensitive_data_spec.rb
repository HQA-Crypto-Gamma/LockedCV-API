# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Sensitive Data Endpoints' do
  include Rack::Test::Methods
  include LockedCV::SpecHelpers

  def app
    LockedCV::Api
  end

  before do
    reset_database!
    @user = LockedCV::User.create(DATA[:users].first.transform_keys(&:to_sym))
    @attachment = @user.add_attachment(DATA[:attachments].first.transform_keys(&:to_sym))
  end

  describe 'POST /api/v1/users/:user_id/attachments/:attachment_id/sensitive_data' do
    it 'HAPPY: creates sensitive data for an attachment' do
      payload = DATA[:sensitive_data].first.transform_keys(&:to_sym)

      post "/api/v1/users/#{@user.id}/attachments/#{@attachment.id}/sensitive_data", payload.to_json, req_header

      _(last_response.status).must_equal 201
      _(last_response.headers['Content-Type']).must_include 'application/json'
      _(json_body['message']).must_equal 'Sensitive data saved'
      _(json_body.dig('data', 'data', 'attributes', 'phone_number')).must_equal payload[:phone_number]
    end

    it 'SAD: returns 400 when sensitive data already exists for attachment' do
      payload = DATA[:sensitive_data].first.transform_keys(&:to_sym)
      LockedCV::SensitiveData.create(payload.merge(attachment_id: @attachment.id))

      post "/api/v1/users/#{@user.id}/attachments/#{@attachment.id}/sensitive_data", payload.to_json, req_header

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Could not save sensitive data')
    end
  end

  describe 'GET /api/v1/users/:user_id/attachments/:attachment_id/sensitive_data' do
    it 'HAPPY: gets sensitive data by attachment' do
      payload = DATA[:sensitive_data].first.transform_keys(&:to_sym)
      sensitive_data = LockedCV::SensitiveData.create(payload.merge(attachment_id: @attachment.id))

      get "/api/v1/users/#{@user.id}/attachments/#{@attachment.id}/sensitive_data"

      _(last_response.status).must_equal 200
      _(last_response.headers['Content-Type']).must_include 'application/json'
      _(json_body.dig('data', 'type')).must_equal 'sensitive_data'
      _(json_body.dig('data', 'attributes', 'id')).must_equal sensitive_data.id
    end

    it 'SAD: returns 404 when sensitive data is missing' do
      another_attachment = @user.add_attachment(attachment_name: 'resume_no_sd.pdf', route: '/uploads/resume_no_sd.pdf')

      get "/api/v1/users/#{@user.id}/attachments/#{another_attachment.id}/sensitive_data"

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Sensitive data not found')
    end
  end
end
