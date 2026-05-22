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

  def stored_attachment(account, filename: 'delete_me.pdf')
    route = "accounts/#{account.id}/#{filename}"
    write_stored_pdf(route, "Stored #{filename}")
    LockedCV::CreateAttachmentService.call(
      account_id: account.id,
      attachment_data: { attachment_name: filename, route: }
    )
  end

  def write_stored_pdf(route, text)
    path = storage_path_for(route)
    FileUtils.mkdir_p(File.dirname(path))
    write_text_pdf(path, text)
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

      post "/api/v1/accounts/#{@account.id}/attachments", payload.to_json, auth_req_header(@account)

      _(last_response.status).must_equal 201
      _(last_response.headers['Content-Type']).must_include 'application/json'
      _(json_body['message']).must_equal 'Attachment saved'
      _(json_body.dig('data', 'data', 'attributes', 'attachment_name')).must_equal payload[:attachment_name]
    end

    it 'SECURITY: returns 400 and does not create attachment on mass assignment' do
      payload = DATA[:attachments].last.merge('account_id' => 'forged-account')
      before_count = LockedCV::Attachment.count

      post "/api/v1/accounts/#{@account.id}/attachments", payload.to_json, auth_req_header(@account)

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

      post "/api/v1/accounts/#{@account.id}/attachments/upload", { file: upload }, auth_header(@account)

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

    it 'HAPPY: stores UTF-8 display filename from form metadata' do
      pdf = Tempfile.new(['lockedcv-api-upload-utf8', '.pdf'])
      write_text_pdf(pdf.path, 'Uploaded PDF text')
      upload = Rack::Test::UploadedFile.new(pdf.path, 'application/pdf', true, original_filename: 'xA1.pdf')

      post(
        "/api/v1/accounts/#{@account.id}/attachments/upload",
        { file: upload, original_filename: '場地單.pdf' },
        auth_header(@account)
      )

      _(last_response.status).must_equal 201
      attachment_name = json_body.dig('data', 'data', 'attributes', 'attachment_name')
      _(attachment_name).must_equal '場地單.pdf'
    ensure
      pdf&.close!
    end

    it 'SAD: rejects non-PDF uploads' do
      text_file = Tempfile.new(['lockedcv-api-upload', '.txt'])
      text_file.write('not a pdf')
      text_file.rewind
      upload = Rack::Test::UploadedFile.new(text_file.path, 'text/plain', true, original_filename: 'resume.txt')

      post "/api/v1/accounts/#{@account.id}/attachments/upload", { file: upload }, auth_header(@account)

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Could not upload attachment')
    ensure
      text_file&.close!
    end

    it 'SAD: rejects missing file uploads' do
      post "/api/v1/accounts/#{@account.id}/attachments/upload", {}, auth_header(@account)

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Could not upload attachment')
    end

    it 'SAD: returns 404 and does not store files when account is missing' do
      pdf = Tempfile.new(['lockedcv-api-upload-missing-account', '.pdf'])
      write_text_pdf(pdf.path, 'Uploaded PDF text')
      upload = Rack::Test::UploadedFile.new(pdf.path, 'application/pdf', true, original_filename: 'resume.pdf')

      post '/api/v1/accounts/missing-account/attachments/upload', { file: upload }, auth_header(@account)

      _(last_response.status).must_equal 403
      _(json_body).must_equal('message' => 'Forbidden account access')
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

      post "/api/v1/accounts/#{@account.id}/attachments/upload", { file: upload }, auth_header(@account)

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Could not upload attachment')
      _(Dir.exist?(storage_path_for("accounts/#{@account.id}"))).must_equal false
    ensure
      pdf&.close!
    end
  end

  describe 'GET /api/v1/attachments' do
    it 'HAPPY: gets all attachments for current account' do
      get '/api/v1/attachments', {}, auth_header(@account)

      _(last_response.status).must_equal 200
      _(last_response.headers['Content-Type']).must_include 'application/json'
      attachment_names = json_body['data'].map { |item| item.dig('data', 'attributes', 'attachment_name') }
      _(attachment_names).must_include DATA[:attachments].first['attachment_name']
    end

    it 'SECURITY: returns 401 without bearer token' do
      get '/api/v1/attachments'

      _(last_response.status).must_equal 401
      _(json_body).must_equal('message' => 'Missing authorization token')
    end

    it 'SECURITY: returns 401 for invalid bearer token' do
      get '/api/v1/attachments', {}, { 'HTTP_AUTHORIZATION' => 'Bearer invalid-token' }

      _(last_response.status).must_equal 401
      _(json_body).must_equal('message' => 'Invalid authorization token')
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/attachments/:attachment_id' do
    it 'HAPPY: deletes attachment metadata and stored files owned by the caller' do
      attachment = stored_attachment(@account)
      masked_route = "accounts/#{@account.id}/masked/masked_delete_me.pdf"
      write_stored_pdf(masked_route, 'Masked PDF text')
      masked_attachment = attachment.add_masked_attachment(
        attachment_name: 'masked_delete_me.pdf',
        route: masked_route
      )
      original_path = storage_path_for(attachment.route)
      masked_path = storage_path_for(masked_route)

      delete "/api/v1/accounts/#{@account.id}/attachments/#{attachment.id}", {}, auth_header(@account)

      _(last_response.status).must_equal 200
      _(json_body).must_equal('message' => 'Attachment deleted')
      _(LockedCV::Attachment.where(id: attachment.id).first).must_be_nil
      _(LockedCV::MaskedAttachment.where(id: masked_attachment.id).first).must_be_nil
      _(File.file?(original_path)).must_equal false
      _(File.file?(masked_path)).must_equal false
    end

    it 'SECURITY: returns 401 when authorization token is missing' do
      attachment = stored_attachment(@account)

      delete "/api/v1/accounts/#{@account.id}/attachments/#{attachment.id}"

      _(last_response.status).must_equal 401
      _(json_body).must_equal('message' => 'Missing authorization token')
    end

    it 'SECURITY: returns 403 when caller does not own the attachment account path' do
      other_account = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].last.transform_keys(&:to_sym)
      )
      attachment = stored_attachment(@account)

      delete "/api/v1/accounts/#{@account.id}/attachments/#{attachment.id}", {}, auth_header(other_account)

      _(last_response.status).must_equal 403
      _(json_body).must_equal('message' => 'Forbidden account access')
    end

    it 'SAD: returns 404 when attachment is missing' do
      delete "/api/v1/accounts/#{@account.id}/attachments/999999", {}, auth_header(@account)

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Attachment not found')
    end

    it 'SECURITY: rejects SQL injection in attachment_id when deleting attachment' do
      attachment = stored_attachment(@account)
      injected_attachment_id = CGI.escape("#{attachment.id}' OR '1'='1")

      delete "/api/v1/accounts/#{@account.id}/attachments/#{injected_attachment_id}", {}, auth_header(@account)

      _(last_response.status).must_equal 404
      _(LockedCV::Attachment.where(id: attachment.id).first).wont_be_nil
      _(File.file?(storage_path_for(attachment.route))).must_equal true
    end
  end

  describe 'GET /api/v1/accounts/:account_id/attachments/:attachment_id' do
    it 'HAPPY: gets one attachment' do
      attachment = @attachments.first

      get "/api/v1/accounts/#{@account.id}/attachments/#{attachment.id}", {}, auth_header(@account)

      _(last_response.status).must_equal 200
      _(json_body.dig('data', 'type')).must_equal 'attachment'
      _(json_body.dig('data', 'attributes', 'id')).must_equal attachment.id
    end

    it 'SAD: returns 404 for missing attachment' do
      get "/api/v1/accounts/#{@account.id}/attachments/999999", {}, auth_header(@account)

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Attachment not found')
    end

    it 'SECURITY: returns 404 when attachment belongs to another account' do
      other_account = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].last.transform_keys(&:to_sym)
      )
      attachment = @attachments.first

      get "/api/v1/accounts/#{other_account.id}/attachments/#{attachment.id}", {}, auth_header(@account)

      _(last_response.status).must_equal 403
      _(json_body).must_equal('message' => 'Forbidden account access')
    end

    it 'SECURITY: rejects SQL injection in attachment_id when fetching attachment' do
      injected_attachment_id = CGI.escape("#{@attachments.first.id}' OR '1'='1")

      get "/api/v1/accounts/#{@account.id}/attachments/#{injected_attachment_id}", {}, auth_header(@account)

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

      get "/api/v1/accounts/#{@account.id}/attachments/#{attachment.id}/masked_text", {}, auth_header(@account)

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

      post "/api/v1/accounts/#{@account.id}/attachments/upload", { file: upload }, auth_header(@account)
      attachment_id = json_body.dig('data', 'data', 'attributes', 'id')
      LockedCV::CreateSensitiveDataService.call(
        account_id: @account.id,
        attachment_id:,
        sensitive_data: DATA[:sensitive_data].first.transform_keys(&:to_sym)
      )

      get "/api/v1/accounts/#{@account.id}/attachments/#{attachment_id}/masked_text", {}, auth_header(@account)

      _(last_response.status).must_equal 200
      _(json_body['data']['attributes']['masked_text']).must_include '[FIRST_NAME]'
      _(json_body['data']['attributes']['masked_text']).must_include '[EMAIL]'
      _(json_body['data']['attributes']['masked_text']).must_include '[PHONE_NUMBER]'
    ensure
      pdf&.close!
    end

    it 'SAD: returns 404 when masking a missing attachment' do
      get "/api/v1/accounts/#{@account.id}/attachments/999999/masked_text", {}, auth_header(@account)

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Attachment not found')
    end
  end

  describe 'POST /api/v1/accounts/:account_id/attachments/:attachment_id/masked_attachments' do
    it 'HAPPY: exports a visual-masked text-based PDF attachment record' do
      upload = Rack::Test::UploadedFile.new(
        'spec/fixtures/files/fake_resume_alan.pdf',
        'application/pdf',
        true,
        original_filename: 'fake_resume_alan.pdf'
      )

      post "/api/v1/accounts/#{@account.id}/attachments/upload", { file: upload }, auth_header(@account)
      attachment_id = json_body.dig('data', 'data', 'attributes', 'id')
      original_route = json_body.dig('data', 'data', 'attributes', 'route')
      LockedCV::CreateSensitiveDataService.call(
        account_id: @account.id,
        attachment_id:,
        sensitive_data: {
          first_name: 'Alan',
          last_name: 'Turing',
          phone_number: '0912-000-002',
          birthday: '1912-06-23',
          email: 'alan@example.com',
          address: 'Manchester',
          identification_numbers: 'B987654321'
        }
      )

      post "/api/v1/accounts/#{@account.id}/attachments/#{attachment_id}/masked_attachments", nil, auth_header(@account)

      _(last_response.status).must_equal 201
      _(json_body['message']).must_equal 'Masked attachment saved'
      route = json_body.dig('data', 'data', 'attributes', 'route')
      _(route).must_match %r{\Aaccounts/#{@account.id}/masked/masked_fake_resume_alan_[0-9a-f]{32}\.pdf\z}
      _(route).wont_match %r{\A/}
      _(File.file?(storage_path_for(route))).must_equal true
      _(File.file?(storage_path_for(original_route))).must_equal true
      _(LockedCV::MaskedAttachment.count).must_equal 1
      _(LockedCV::MaskedItem.count).must_be :>, 0
      scrubbed_text = LockedCV::ExtractPdf.text(storage_path_for(route))
      _(scrubbed_text).wont_include 'Alan Turing'
      _(scrubbed_text).wont_include 'alan@example.com'
      _(scrubbed_text).wont_include '0912-000-002'
      _(scrubbed_text).wont_include 'B987654321'
      _(scrubbed_text).wont_include '@example.com'
      _(scrubbed_text).wont_include '0912'
      _(scrubbed_text).wont_include 'B987'
    end

    it 'SAD: returns 404 when exporting a missing attachment' do
      post "/api/v1/accounts/#{@account.id}/attachments/999999/masked_attachments", nil, auth_header(@account)

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Attachment not found')
    end
  end
end
