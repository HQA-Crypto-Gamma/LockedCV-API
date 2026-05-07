# frozen_string_literal: true

require 'cgi'
require 'tempfile'
require_relative '../spec_helper'

describe 'Attachment Endpoints' do
  include Rack::Test::Methods
  include LockedCV::SpecHelpers

  def app
    LockedCV::Api
  end

  before do
    reset_database!
    reset_storage!
    @account = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )
    @attachments = [
      LockedCV::CreateAttachmentService.call(
        account_id: @account.id,
        attachment_data: DATA[:attachments].first.transform_keys(&:to_sym)
      )
    ]
  end

  after do
    reset_storage!
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

  describe 'POST /api/v1/accounts/:account_id/attachments/upload' do
    it 'HAPPY: uploads a PDF and stores attachment metadata with a relative route' do
      pdf = Tempfile.new(['lockedcv-api-upload', '.pdf'])
      write_text_pdf(pdf.path, 'Uploaded PDF text')
      upload = Rack::Test::UploadedFile.new(pdf.path, 'application/pdf', true, original_filename: 'Resume Ada.pdf')

      post "/api/v1/accounts/#{@account.id}/attachments/upload", { file: upload }

      _(last_response.status).must_equal 201
      _(last_response.headers['Content-Type']).must_include 'application/json'
      _(json_body['message']).must_equal 'Attachment saved'
      route = json_body.dig('data', 'data', 'attributes', 'route')
      _(route).must_match %r{\Aaccounts/#{@account.id}/resume_ada_[0-9a-f]{32}\.pdf\z}
      _(route).wont_match %r{\A/}
      _(File.file?(storage_path_for(route))).must_equal true
    ensure
      pdf&.close!
    end

    it 'SAD: rejects non-PDF uploads' do
      text_file = Tempfile.new(['lockedcv-api-upload', '.txt'])
      text_file.write('not a pdf')
      text_file.rewind
      upload = Rack::Test::UploadedFile.new(text_file.path, 'text/plain', true, original_filename: 'resume.txt')

      post "/api/v1/accounts/#{@account.id}/attachments/upload", { file: upload }

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Could not upload attachment')
    ensure
      text_file&.close!
    end

    it 'SAD: rejects missing file uploads' do
      post "/api/v1/accounts/#{@account.id}/attachments/upload", {}

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Could not upload attachment')
    end

    it 'SAD: returns 404 and does not store files when account is missing' do
      pdf = Tempfile.new(['lockedcv-api-upload-missing-account', '.pdf'])
      write_text_pdf(pdf.path, 'Uploaded PDF text')
      upload = Rack::Test::UploadedFile.new(pdf.path, 'application/pdf', true, original_filename: 'resume.pdf')

      post '/api/v1/accounts/missing-account/attachments/upload', { file: upload }

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Account not found')
      _(Dir.exist?(storage_path_for('accounts/missing-account'))).must_equal false
    ensure
      pdf&.close!
    end

    it 'SAD: deletes uploaded files when attachment metadata cannot be saved' do
      pdf = Tempfile.new(['lockedcv-api-upload-duplicate', '.pdf'])
      write_text_pdf(pdf.path, 'Uploaded PDF text')
      upload = Rack::Test::UploadedFile.new(
        pdf.path,
        'application/pdf',
        true,
        original_filename: DATA[:attachments].first['attachment_name']
      )

      post "/api/v1/accounts/#{@account.id}/attachments/upload", { file: upload }

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Could not upload attachment')
      _(Dir.exist?(storage_path_for("accounts/#{@account.id}"))).must_equal false
    ensure
      pdf&.close!
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

    it 'SECURITY: rejects SQL injection in account_id when fetching attachments' do
      injected_account_id = CGI.escape("#{@account.id}' OR '1'='1")

      get "/api/v1/accounts/#{injected_account_id}/attachments"

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

    it 'SECURITY: returns 404 when attachment belongs to another account' do
      other_account = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].last.transform_keys(&:to_sym)
      )
      attachment = @attachments.first

      get "/api/v1/accounts/#{other_account.id}/attachments/#{attachment.id}"

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Attachment not found')
    end

    it 'SECURITY: rejects SQL injection in attachment_id when fetching attachment' do
      injected_attachment_id = CGI.escape("#{@attachments.first.id}' OR '1'='1")

      get "/api/v1/accounts/#{@account.id}/attachments/#{injected_attachment_id}"

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Attachment not found')
    end
  end

  describe 'GET /api/v1/accounts/:account_id/attachments/:attachment_id/masked_text' do
    it 'HAPPY: returns masked text for a text-based PDF attachment' do
      pdf = Tempfile.new(['lockedcv-api-attachment', '.pdf'])
      write_text_pdf(pdf.path, 'Ada: ada@example.com, 0912-000-001, 1815-12-10, A123456789')
      stored_route = nil
      File.open(pdf.path, 'rb') do |uploaded_pdf|
        stored_route = LockedCV::StoreAttachmentFile.call(
          uploaded_file: {
            filename: 'resume_maskable.pdf',
            type: 'application/pdf',
            tempfile: uploaded_pdf
          },
          account_id: @account.id
        )
      end
      attachment = LockedCV::CreateAttachmentService.call(
        account_id: @account.id,
        attachment_data: {
          attachment_name: 'resume_maskable.pdf',
          route: stored_route
        }
      )
      LockedCV::CreateSensitiveDataService.call(
        account_id: @account.id,
        attachment_id: attachment.id,
        sensitive_data: DATA[:sensitive_data].first.transform_keys(&:to_sym)
      )

      get "/api/v1/accounts/#{@account.id}/attachments/#{attachment.id}/masked_text"

      _(last_response.status).must_equal 200
      _(last_response.headers['Content-Type']).must_include 'application/json'
      _(json_body['data']['type']).must_equal 'masked_attachment_text'
      _(json_body['data']['attributes']['attachment_id']).must_equal attachment.id
      _(json_body['data']['attributes']['masked_text']).must_include '[FIRST_NAME]'
      _(json_body['data']['attributes']['masked_text']).must_include '[EMAIL]'
      _(json_body['data']['attributes']['masked_text']).must_include '[PHONE_NUMBER]'
      _(json_body['data']['attributes']['masked_text']).must_include '[BIRTHDAY]'
      _(json_body['data']['attributes']['masked_text']).must_include '[IDENTIFICATION_NUMBERS]'
    ensure
      pdf&.close!
    end

    it 'HAPPY: masks text from an uploaded PDF through the storage resolver' do
      pdf = Tempfile.new(['lockedcv-api-mask-upload', '.pdf'])
      write_text_pdf(pdf.path, 'Ada Lovelace email ada@example.com phone 0912-000-001')
      upload = Rack::Test::UploadedFile.new(pdf.path, 'application/pdf', true, original_filename: 'maskable.pdf')

      post "/api/v1/accounts/#{@account.id}/attachments/upload", { file: upload }
      attachment_id = json_body.dig('data', 'data', 'attributes', 'id')
      LockedCV::CreateSensitiveDataService.call(
        account_id: @account.id,
        attachment_id:,
        sensitive_data: DATA[:sensitive_data].first.transform_keys(&:to_sym)
      )

      get "/api/v1/accounts/#{@account.id}/attachments/#{attachment_id}/masked_text"

      _(last_response.status).must_equal 200
      _(json_body['data']['attributes']['masked_text']).must_include '[FIRST_NAME]'
      _(json_body['data']['attributes']['masked_text']).must_include '[EMAIL]'
      _(json_body['data']['attributes']['masked_text']).must_include '[PHONE_NUMBER]'
    ensure
      pdf&.close!
    end

    it 'SAD: returns 404 when masking a missing attachment' do
      get "/api/v1/accounts/#{@account.id}/attachments/999999/masked_text"

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Attachment not found')
    end
  end
end
