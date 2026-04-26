# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Attachment Endpoints' do
  include Rack::Test::Methods
  include LockedCV::SpecHelpers

  def app
    LockedCV::Api
  end

  before do
    reset_database!
    @account = LockedCV::Account.create(DATA[:accounts].first.transform_keys(&:to_sym))
    @attachments = [@account.add_attachment(DATA[:attachments].first.transform_keys(&:to_sym))]
  end

  describe 'POST /api/v1/accounts/:account_id/attachments' do
    it 'HAPPY: creates an attachment for an account' do
      payload = DATA[:attachments].last.transform_keys(&:to_sym)

      post "/api/v1/accounts/#{@account.id}/attachments", payload.to_json, req_header

      _(last_response.status).must_equal 201
      _(last_response.headers['Content-Type']).must_include 'application/json'
      _(json_body['message']).must_equal 'Attachment saved'
      _(json_body.dig('data', 'data', 'attributes', 'attachment_name')).must_equal payload[:attachment_name]
    end

    it 'SECURITY: returns 400 and does not create attachment on mass assignment' do
      payload = DATA[:attachments].last.merge('account_id' => 'forged-account')
      before_count = LockedCV::Attachment.count

      post "/api/v1/accounts/#{@account.id}/attachments", payload.to_json, req_header

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Illegal attributes')
      _(LockedCV::Attachment.count).must_equal before_count
      _(LockedCV::Attachment.where(account_id: 'forged-account').count).must_equal 0
    end
  end

  describe 'GET /api/v1/accounts/:account_id/attachments' do
    it 'HAPPY: gets all attachments for an account' do
      get "/api/v1/accounts/#{@account.id}/attachments"

      _(last_response.status).must_equal 200
      _(last_response.headers['Content-Type']).must_include 'application/json'
      attachment_names = json_body['data'].map { |item| item.dig('data', 'attributes', 'attachment_name') }
      _(attachment_names).must_include DATA[:attachments].first['attachment_name']
    end

    it 'SAD: returns 404 for missing account' do
      get '/api/v1/accounts/999999/attachments'

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Could not find attachments')
    end
  end

  describe 'GET /api/v1/accounts/:account_id/attachments/:attachment_id' do
    it 'HAPPY: gets one attachment' do
      attachment = @attachments.first

      get "/api/v1/accounts/#{@account.id}/attachments/#{attachment.id}"

      _(last_response.status).must_equal 200
      _(json_body.dig('data', 'type')).must_equal 'attachment'
      _(json_body.dig('data', 'attributes', 'id')).must_equal attachment.id
    end

    it 'SAD: returns 404 for missing attachment' do
      get "/api/v1/accounts/#{@account.id}/attachments/999999"

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Attachment not found')
    end
  end
end
