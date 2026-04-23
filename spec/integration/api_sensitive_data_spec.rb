# frozen_string_literal: true

require_relative '../spec_helper'
require 'cgi'

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

    it 'SAD: returns 400 and does not create sensitive data on mass assignment' do
      payload = DATA[:sensitive_data].first.merge('attachment_id' => 'forged-attachment')
      before_count = LockedCV::SensitiveData.count

      post "/api/v1/users/#{@user.id}/attachments/#{@attachment.id}/sensitive_data", payload.to_json, req_header

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Illegal attributes')
      _(LockedCV::SensitiveData.count).must_equal before_count
      _(LockedCV::SensitiveData.where(attachment_id: 'forged-attachment').count).must_equal 0
    end

    it 'SAD: returns 400 when sensitive data already exists for attachment' do
      payload = DATA[:sensitive_data].first.transform_keys(&:to_sym)
      sensitive_data = LockedCV::SensitiveData.new(payload)
      sensitive_data.attachment_id = @attachment.id
      sensitive_data.save

      post "/api/v1/users/#{@user.id}/attachments/#{@attachment.id}/sensitive_data", payload.to_json, req_header

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Could not save sensitive data')
    end

    it 'SAD: rejects SQL injection in attachment_id and creates no sensitive data' do
      payload = DATA[:sensitive_data].first.transform_keys(&:to_sym)
      injected_attachment_id = CGI.escape("#{@attachment.id}' OR '1'='1")
      before_count = LockedCV::SensitiveData.count

      post "/api/v1/users/#{@user.id}/attachments/#{injected_attachment_id}/sensitive_data", payload.to_json, req_header

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Could not save sensitive data')
      _(LockedCV::SensitiveData.count).must_equal before_count
    end
  end

  describe 'GET /api/v1/users/:user_id/attachments/:attachment_id/sensitive_data' do
    it 'HAPPY: gets sensitive data by attachment' do
      payload = DATA[:sensitive_data].first.transform_keys(&:to_sym)
      sensitive_data = LockedCV::SensitiveData.new(payload)
      sensitive_data.attachment_id = @attachment.id
      sensitive_data.save

      get "/api/v1/users/#{@user.id}/attachments/#{@attachment.id}/sensitive_data"

      _(last_response.status).must_equal 200
      _(last_response.headers['Content-Type']).must_include 'application/json'
      _(json_body.dig('data', 'type')).must_equal 'sensitive_data'
      _(json_body.dig('data', 'attributes', 'id')).must_equal sensitive_data.id
    end

    it 'SAD: rejects SQL injection in user_id when fetching sensitive data' do
      payload = DATA[:sensitive_data].first.transform_keys(&:to_sym)
      sensitive_data = LockedCV::SensitiveData.new(payload)
      sensitive_data.attachment_id = @attachment.id
      sensitive_data.save
      injected_user_id = CGI.escape("#{@user.id}' OR '1'='1")

      get "/api/v1/users/#{injected_user_id}/attachments/#{@attachment.id}/sensitive_data"

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Sensitive data not found')
    end

    it 'SAD: rejects SQL injection in attachment_id when fetching sensitive data' do
      payload = DATA[:sensitive_data].first.transform_keys(&:to_sym)
      sensitive_data = LockedCV::SensitiveData.new(payload)
      sensitive_data.attachment_id = @attachment.id
      sensitive_data.save
      injected_attachment_id = CGI.escape("#{@attachment.id}' OR '1'='1")

      get "/api/v1/users/#{@user.id}/attachments/#{injected_attachment_id}/sensitive_data"

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Sensitive data not found')
    end

    it 'SAD: returns 404 when sensitive data is missing' do
      another_attachment = @user.add_attachment(attachment_name: 'resume_no_sd.pdf', route: '/uploads/resume_no_sd.pdf')

      get "/api/v1/users/#{@user.id}/attachments/#{another_attachment.id}/sensitive_data"

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Sensitive data not found')
    end
  end
end
