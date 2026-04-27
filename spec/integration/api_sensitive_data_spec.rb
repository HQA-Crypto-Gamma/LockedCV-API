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
    @account = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )
    @attachment = LockedCV::CreateAttachmentService.call(
      account_id: @account.id,
      attachment_data: DATA[:attachments].first.transform_keys(&:to_sym)
    )
  end

  describe 'POST /api/v1/accounts/:account_id/attachments/:attachment_id/sensitive_data' do
    it 'HAPPY: creates sensitive data for an attachment' do
      payload = DATA[:sensitive_data].first.transform_keys(&:to_sym)

      post "/api/v1/accounts/#{@account.id}/attachments/#{@attachment.id}/sensitive_data", payload.to_json, req_header

      _(last_response.status).must_equal 201
      _(last_response.headers['Content-Type']).must_include 'application/json'
      _(json_body['message']).must_equal 'Sensitive data saved'
      _(json_body.dig('data', 'data', 'attributes', 'first_name')).must_equal payload[:first_name]
    end

    it 'SECURITY: returns 400 and does not create sensitive data on mass assignment' do
      payload = DATA[:sensitive_data].first.merge('attachment_id' => 'forged-attachment')
      before_count = LockedCV::SensitiveData.count

      post "/api/v1/accounts/#{@account.id}/attachments/#{@attachment.id}/sensitive_data", payload.to_json, req_header

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Illegal attributes')
      _(LockedCV::SensitiveData.count).must_equal before_count
      _(LockedCV::SensitiveData.where(attachment_id: 'forged-attachment').count).must_equal 0
    end

    it 'SAD: returns 400 when sensitive data already exists for attachment' do
      payload = DATA[:sensitive_data].first.transform_keys(&:to_sym)
      LockedCV::CreateSensitiveDataService.call(
        account_id: @account.id,
        attachment_id: @attachment.id,
        sensitive_data: payload
      )

      post "/api/v1/accounts/#{@account.id}/attachments/#{@attachment.id}/sensitive_data", payload.to_json, req_header

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Could not save sensitive data')
    end

    it 'SECURITY: rejects SQL injection in attachment_id and creates no sensitive data' do
      payload = DATA[:sensitive_data].first.transform_keys(&:to_sym)
      injected_attachment_id = CGI.escape("#{@attachment.id}' OR '1'='1")
      before_count = LockedCV::SensitiveData.count

      post "/api/v1/accounts/#{@account.id}/attachments/#{injected_attachment_id}/sensitive_data",
           payload.to_json, req_header

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Sensitive data not found')
      _(LockedCV::SensitiveData.count).must_equal before_count
    end

    it 'SAD: returns 404 when attachment path resource is missing' do
      payload = DATA[:sensitive_data].first.transform_keys(&:to_sym)
      before_count = LockedCV::SensitiveData.count

      post "/api/v1/accounts/#{@account.id}/attachments/999999/sensitive_data", payload.to_json, req_header

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Sensitive data not found')
      _(LockedCV::SensitiveData.count).must_equal before_count
    end
  end

  describe 'GET /api/v1/accounts/:account_id/attachments/:attachment_id/sensitive_data' do
    it 'HAPPY: gets sensitive data by attachment' do
      payload = DATA[:sensitive_data].first.transform_keys(&:to_sym)
      sensitive_data = LockedCV::CreateSensitiveDataService.call(
        account_id: @account.id,
        attachment_id: @attachment.id,
        sensitive_data: payload
      )

      get "/api/v1/accounts/#{@account.id}/attachments/#{@attachment.id}/sensitive_data"

      _(last_response.status).must_equal 200
      _(last_response.headers['Content-Type']).must_include 'application/json'
      _(json_body.dig('data', 'type')).must_equal 'sensitive_data'
      _(json_body.dig('data', 'attributes', 'id')).must_equal sensitive_data.id
    end

    it 'SECURITY: rejects SQL injection in account_id when fetching sensitive data' do
      payload = DATA[:sensitive_data].first.transform_keys(&:to_sym)
      LockedCV::CreateSensitiveDataService.call(
        account_id: @account.id,
        attachment_id: @attachment.id,
        sensitive_data: payload
      )
      injected_account_id = CGI.escape("#{@account.id}' OR '1'='1")

      get "/api/v1/accounts/#{injected_account_id}/attachments/#{@attachment.id}/sensitive_data"

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Sensitive data not found')
    end

    it 'SECURITY: rejects SQL injection in attachment_id when fetching sensitive data' do
      payload = DATA[:sensitive_data].first.transform_keys(&:to_sym)
      LockedCV::CreateSensitiveDataService.call(
        account_id: @account.id,
        attachment_id: @attachment.id,
        sensitive_data: payload
      )
      injected_attachment_id = CGI.escape("#{@attachment.id}' OR '1'='1")

      get "/api/v1/accounts/#{@account.id}/attachments/#{injected_attachment_id}/sensitive_data"

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Sensitive data not found')
    end

    it 'SAD: returns 404 when sensitive data is missing' do
      another_attachment = LockedCV::CreateAttachmentService.call(
        account_id: @account.id,
        attachment_data: {
          attachment_name: 'resume_no_sd.pdf',
          route: '/uploads/resume_no_sd.pdf'
        }
      )

      get "/api/v1/accounts/#{@account.id}/attachments/#{another_attachment.id}/sensitive_data"

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Sensitive data not found')
    end
  end
end
