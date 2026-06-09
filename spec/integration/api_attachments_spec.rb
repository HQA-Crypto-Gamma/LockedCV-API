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

  def upload_fake_resume_with_sensitive_data
    post '/api/v1/attachments/upload', { file: fake_resume_upload }, auth_header(@account)
    attachment_id = json_body.dig('data', 'data', 'attributes', 'id')
    LockedCV::CreateSensitiveDataService.call(
      account_id: @account.id,
      attachment_id:,
      sensitive_data: fake_resume_sensitive_data
    )

    attachment_id
  end

  def fake_resume_upload
    Rack::Test::UploadedFile.new(
      'spec/fixtures/files/fake_resume_alan.pdf',
      'application/pdf',
      true,
      original_filename: 'fake_resume_alan.pdf'
    )
  end

  def fake_resume_sensitive_data
    {
      first_name: 'Alan',
      last_name: 'Turing',
      phone_number: '0912-000-002',
      birthday: '1912-06-23',
      email: 'alan@example.com',
      address: 'Manchester',
      identification_numbers: 'B987654321'
    }
  end

  def create_masked_attachment_with_selected_labels(labels)
    attachment_id = upload_fake_resume_with_sensitive_data
    python_bin = available_pdf_processor_python
    skip 'pdfplumber/reportlab Python dependencies are not available' unless python_bin

    post_create_masked_attachment(attachment_id, labels, python_bin)

    [attachment_id, json_body.dig('data', 'data', 'attributes', 'id')]
  end

  def saved_masked_attachment_for(account = @account)
    attachment = stored_attachment(account, filename: 'share_source.pdf')
    masked_route = "accounts/#{account.id}/masked/share_masked_#{attachment.id}.pdf"
    write_stored_pdf(masked_route, 'Alan Turing shared masked PDF')
    masked_attachment = attachment.add_masked_attachment(
      attachment_name: 'share_masked.pdf',
      route: masked_route
    )

    [attachment, masked_attachment]
  end

  def create_masked_attachment_share_link(attachment, masked_attachment, account = @account)
    post(
      "/api/v1/attachments/#{attachment.id}/masked_attachments/#{masked_attachment.id}/share_links",
      {}.to_json,
      auth_req_header(account)
    )
  end

  def post_create_masked_attachment(attachment_id, labels, python_bin)
    with_python_bin(python_bin) do
      post(
        "/api/v1/attachments/#{attachment_id}/masked_attachments",
        { selected_labels: labels }.to_json,
        auth_req_header(@account)
      )
    end
  end

  def command_available?(command)
    _stdout, _stderr, status = Open3.capture3('which', command)
    status.success?
  rescue SystemCallError
    false
  end

  def recipient_account(username: 'masked-share-recipient')
    LockedCV::CreateAccountService.call(
      account_data: {
        username:,
        email: "#{username}@example.com",
        password: 'recipient-secret'
      }
    )
  end

  def viewer_masked_account_for(attachment_id)
    viewer = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].last.transform_keys(&:to_sym)
    )
    LockedCV::AttachmentPermission.create(
      account_id: viewer.id,
      attachment_id:,
      role: 'viewer_masked'
    )

    viewer
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

  describe 'POST /api/v1/attachments/upload' do
    it 'HAPPY: uploads a PDF for the bearer-token account' do
      pdf = Tempfile.new(['lockedcv-api-current-upload', '.pdf'])
      write_text_pdf(pdf.path, 'Uploaded PDF text')
      upload = Rack::Test::UploadedFile.new(pdf.path, 'application/pdf', true, original_filename: 'Resume Ada.pdf')

      post '/api/v1/attachments/upload', { file: upload }, auth_header(@account)

      _(last_response.status).must_equal 201
      _(json_body['message']).must_equal 'Attachment saved'
      attachment_id = json_body.dig('data', 'data', 'attributes', 'id')
      _(last_response.headers['Location']).must_equal "api/v1/attachments/#{attachment_id}"
      route = json_body.dig('data', 'data', 'attributes', 'route')
      _(route).must_match %r{\Aaccounts/#{@account.id}/resume_ada_[0-9a-f]{32}\.pdf\z}
      _(File.file?(storage_path_for(route))).must_equal true
    ensure
      pdf&.close!
    end

    it 'SECURITY: returns 401 when authorization token is missing' do
      pdf = Tempfile.new(['lockedcv-api-current-upload-no-token', '.pdf'])
      write_text_pdf(pdf.path, 'Uploaded PDF text')
      upload = Rack::Test::UploadedFile.new(pdf.path, 'application/pdf', true, original_filename: 'resume.pdf')

      post '/api/v1/attachments/upload', { file: upload }

      _(last_response.status).must_equal 401
      _(json_body).must_equal('message' => 'Missing authorization token')
    ensure
      pdf&.close!
    end

    it 'SECURITY: rejects uploads from read-only tokens' do
      pdf = Tempfile.new(['lockedcv-api-read-only-upload', '.pdf'])
      write_text_pdf(pdf.path, 'Uploaded PDF text')
      upload = Rack::Test::UploadedFile.new(pdf.path, 'application/pdf', true, original_filename: 'resume.pdf')
      read_only = LockedCV::AuthScope.new(LockedCV::AuthScope::READ_ONLY)

      post '/api/v1/attachments/upload', { file: upload }, auth_header(@account, scope: read_only)

      _(last_response.status).must_equal 403
      _(json_body).must_equal('message' => 'Only members can upload attachments')
    ensure
      pdf&.close!
    end

    it 'SAD: rejects missing file uploads' do
      post '/api/v1/attachments/upload', {}, auth_header(@account)

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Could not upload attachment')
    end

    it 'HAPPY: stores UTF-8 display filename from form metadata' do
      pdf = Tempfile.new(['lockedcv-api-upload-utf8', '.pdf'])
      write_text_pdf(pdf.path, 'Uploaded PDF text')
      upload = Rack::Test::UploadedFile.new(pdf.path, 'application/pdf', true, original_filename: 'xA1.pdf')

      post('/api/v1/attachments/upload', { file: upload, original_filename: '場地單.pdf' }, auth_header(@account))

      _(last_response.status).must_equal 201
      attachment_name = json_body.dig('data', 'data', 'attributes', 'attachment_name')
      _(attachment_name).must_equal '場地單.pdf'
    ensure
      pdf&.close!
    end

    it 'HAPPY: lets admins upload attachments without a member role' do
      admin_role = LockedCV::Role.find_or_create(name: 'admin')
      admin = LockedCV::CreateAccountService.call(
        account_data: {
          username: 'admin-uploader',
          email: 'admin-uploader@example.com',
          phone_number: '0912-900-001',
          password: 'admin-secret'
        }
      )
      LockedCV::SetSystemRoleService.call(account: admin, role_name: admin_role.name)
      pdf = Tempfile.new(['lockedcv-api-admin-upload', '.pdf'])
      write_text_pdf(pdf.path, 'Admin uploaded PDF text')
      upload = Rack::Test::UploadedFile.new(pdf.path, 'application/pdf', true, original_filename: 'admin.pdf')

      post '/api/v1/attachments/upload', { file: upload }, auth_header(admin)

      _(last_response.status).must_equal 201
      _(admin.reload.system_roles.map(&:name)).must_equal ['admin']
      route = json_body.dig('data', 'data', 'attributes', 'route')
      _(route).must_match %r{\Aaccounts/#{admin.id}/admin_[0-9a-f]{32}\.pdf\z}
    ensure
      pdf&.close!
    end

    it 'SAD: rejects non-PDF uploads' do
      text_file = Tempfile.new(['lockedcv-api-upload', '.txt'])
      text_file.write('not a pdf')
      text_file.rewind
      upload = Rack::Test::UploadedFile.new(text_file.path, 'text/plain', true, original_filename: 'resume.txt')

      post '/api/v1/attachments/upload', { file: upload }, auth_header(@account)

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Could not upload attachment')
    ensure
      text_file&.close!
    end

    it 'HAPPY: numbers duplicate display filenames within an account' do
      pdfs = Array.new(3) do |index|
        Tempfile.new(["lockedcv-api-upload-duplicate-#{index}", '.pdf']).tap do |pdf|
          write_text_pdf(pdf.path, "Uploaded PDF text #{index}")
        end
      end

      attachment_names = pdfs.map do |pdf|
        upload = Rack::Test::UploadedFile.new(
          pdf.path,
          'application/pdf',
          true,
          original_filename: DATA[:attachments].first['attachment_name']
        )

        post '/api/v1/attachments/upload', { file: upload }, auth_header(@account)

        _(last_response.status).must_equal 201
        json_body.dig('data', 'data', 'attributes', 'attachment_name')
      end

      _(attachment_names).must_equal [
        'resume_ada (1).pdf',
        'resume_ada (2).pdf',
        'resume_ada (3).pdf'
      ]
    ensure
      pdfs&.each(&:close!)
    end
  end

  describe 'GET /api/v1/attachments' do
    it 'HAPPY: gets scoped attachments with policy summaries for current account' do
      @attachments.first.add_masked_attachment(
        attachment_name: 'masked_resume_ada.pdf',
        route: "accounts/#{@account.id}/masked/masked_resume_ada.pdf"
      )
      shared_owner = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].last.transform_keys(&:to_sym)
      )
      shared_attachment = LockedCV::CreateAttachmentService.call(
        account_id: shared_owner.id,
        attachment_data: {
          attachment_name: 'shared_masked.pdf',
          route: "accounts/#{shared_owner.id}/shared_masked.pdf"
        }
      )
      LockedCV::AttachmentPermission.create(
        account_id: @account.id,
        attachment_id: shared_attachment.id,
        role: 'viewer_masked'
      )
      unrelated_account = LockedCV::CreateAccountService.call(
        account_data: {
          username: 'unrelated-attachment-owner',
          email: 'unrelated-attachment-owner@example.com',
          phone_number: '0912-900-002',
          password: 'unrelated-secret'
        }
      )
      unrelated_attachment = LockedCV::CreateAttachmentService.call(
        account_id: unrelated_account.id,
        attachment_data: {
          attachment_name: 'unrelated.pdf',
          route: "accounts/#{unrelated_account.id}/unrelated.pdf"
        }
      )

      get '/api/v1/attachments', {}, auth_header(@account)

      _(last_response.status).must_equal 200
      _(last_response.headers['Content-Type']).must_include 'application/json'

      attachments = json_body['data']
      attachment_ids = attachments.map { |item| item.dig('data', 'attributes', 'id') }
      _(attachment_ids).must_include @attachments.first.id
      _(attachment_ids).must_include shared_attachment.id
      _(attachment_ids).wont_include unrelated_attachment.id

      owned_attachment = attachments.find { |item| item.dig('data', 'attributes', 'id') == @attachments.first.id }
      owned_attachment_name = owned_attachment.dig('data', 'attributes', 'attachment_name')
      _(owned_attachment_name).must_equal DATA[:attachments].first['attachment_name']
      _(owned_attachment.dig('data', 'attributes', 'masked_attachments_count')).must_equal 1
      _(owned_attachment.dig('data', 'attributes', 'created_at')).wont_be_nil
      _(owned_attachment['policy']).must_equal(
        'can_view' => true,
        'can_view_masked' => true,
        'can_access' => true,
        'can_upload' => true,
        'can_delete' => true,
        'role' => 'owner'
      )

      shared_entry = attachments.find { |item| item.dig('data', 'attributes', 'id') == shared_attachment.id }
      _(shared_entry.dig('data', 'attributes', 'attachment_name')).must_equal 'shared_masked.pdf'
      _(shared_entry['policy']).must_equal(
        'can_view' => false,
        'can_view_masked' => true,
        'can_access' => true,
        'can_upload' => true,
        'can_delete' => false,
        'role' => 'viewer_masked'
      )
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

  describe 'GET /api/v1/attachments/:attachment_id/masked_attachments' do
    it 'HAPPY: lists saved masked PDF versions for an attachment' do
      attachment = @attachments.first
      masked_attachment = attachment.add_masked_attachment(
        attachment_name: 'masked_resume_ada.pdf',
        route: "accounts/#{@account.id}/masked/masked_resume_ada.pdf"
      )
      masked_attachment.add_masked_item(
        field_name: 'email',
        value: 'ada@example.com',
        source: 'regex'
      )

      get "/api/v1/attachments/#{attachment.id}/masked_attachments", {}, auth_header(@account)

      _(last_response.status).must_equal 200
      versions = json_body['data']
      _(versions.length).must_equal 1
      attributes = versions.first.dig('data', 'attributes')
      _(attributes['id']).must_equal masked_attachment.id
      _(attributes['attachment_id']).must_equal attachment.id
      _(attributes['attachment_name']).must_equal 'masked_resume_ada.pdf'
      _(attributes['masked_items_count']).must_equal 1
    end

    it 'SECURITY: rejects masked version listing for unrelated accounts' do
      attachment = @attachments.first
      other_account = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].last.transform_keys(&:to_sym)
      )

      get "/api/v1/attachments/#{attachment.id}/masked_attachments", {}, auth_header(other_account)

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Attachment not found')
    end
  end

  describe 'DELETE /api/v1/attachments/:attachment_id/masked_attachments/:masked_attachment_id' do
    it 'HAPPY: deletes one saved masked PDF version without deleting the source attachment' do
      attachment = stored_attachment(@account)
      masked_route = "accounts/#{@account.id}/masked/masked_delete_one.pdf"
      write_stored_pdf(masked_route, 'Masked PDF text')
      masked_attachment = attachment.add_masked_attachment(
        attachment_name: 'masked_delete_one.pdf',
        route: masked_route
      )
      masked_path = storage_path_for(masked_route)

      delete(
        "/api/v1/attachments/#{attachment.id}/masked_attachments/#{masked_attachment.id}",
        {},
        auth_header(@account)
      )

      _(last_response.status).must_equal 200
      _(json_body).must_equal('message' => 'Masked attachment deleted')
      _(LockedCV::Attachment.where(id: attachment.id).first).wont_be_nil
      _(LockedCV::MaskedAttachment.where(id: masked_attachment.id).first).must_be_nil
      _(File.file?(masked_path)).must_equal false
    end

    it 'SECURITY: rejects masked version deletes from unrelated accounts' do
      attachment = stored_attachment(@account)
      masked_attachment = attachment.add_masked_attachment(
        attachment_name: 'masked_private.pdf',
        route: "accounts/#{@account.id}/masked/masked_private.pdf"
      )
      other_account = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].last.transform_keys(&:to_sym)
      )

      delete(
        "/api/v1/attachments/#{attachment.id}/masked_attachments/#{masked_attachment.id}",
        {},
        auth_header(other_account)
      )

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Masked attachment not found')
      _(LockedCV::MaskedAttachment.where(id: masked_attachment.id).first).wont_be_nil
    end

    it 'SAD: returns 404 when the masked version is missing' do
      attachment = stored_attachment(@account)

      delete "/api/v1/attachments/#{attachment.id}/masked_attachments/999999", {}, auth_header(@account)

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Masked attachment not found')
    end
  end

  describe 'DELETE /api/v1/attachments/:attachment_id' do
    it 'HAPPY: deletes attachment metadata and stored files for the bearer-token account' do
      attachment = stored_attachment(@account)
      masked_route = "accounts/#{@account.id}/masked/masked_delete_me.pdf"
      write_stored_pdf(masked_route, 'Masked PDF text')
      masked_attachment = attachment.add_masked_attachment(
        attachment_name: 'masked_delete_me.pdf',
        route: masked_route
      )
      original_path = storage_path_for(attachment.route)
      masked_path = storage_path_for(masked_route)

      delete "/api/v1/attachments/#{attachment.id}", {}, auth_header(@account)

      _(last_response.status).must_equal 200
      _(json_body).must_equal('message' => 'Attachment deleted')
      _(LockedCV::Attachment.where(id: attachment.id).first).must_be_nil
      _(LockedCV::MaskedAttachment.where(id: masked_attachment.id).first).must_be_nil
      _(File.file?(original_path)).must_equal false
      _(File.file?(masked_path)).must_equal false
    end

    it 'SECURITY: returns 401 when authorization token is missing' do
      attachment = stored_attachment(@account)

      delete "/api/v1/attachments/#{attachment.id}"

      _(last_response.status).must_equal 401
      _(json_body).must_equal('message' => 'Missing authorization token')
    end

    it 'SECURITY: rejects deletes from read-only tokens' do
      attachment = stored_attachment(@account)
      read_only = LockedCV::AuthScope.new(LockedCV::AuthScope::READ_ONLY)

      delete "/api/v1/attachments/#{attachment.id}", {}, auth_header(@account, scope: read_only)

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Attachment not found')
      _(LockedCV::Attachment.where(id: attachment.id).first).wont_be_nil
    end

    it 'SECURITY: returns 404 when attachment belongs to another account' do
      other_account = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].last.transform_keys(&:to_sym)
      )
      attachment = stored_attachment(@account)

      delete "/api/v1/attachments/#{attachment.id}", {}, auth_header(other_account)

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Attachment not found')
      _(LockedCV::Attachment.where(id: attachment.id).first).wont_be_nil
    end

    it 'SAD: returns 404 when attachment is missing' do
      delete '/api/v1/attachments/999999', {}, auth_header(@account)

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Attachment not found')
    end

    it 'SECURITY: rejects SQL injection in attachment_id when deleting attachment' do
      attachment = stored_attachment(@account)
      injected_attachment_id = CGI.escape("#{attachment.id}' OR '1'='1")

      delete "/api/v1/attachments/#{injected_attachment_id}", {}, auth_header(@account)

      _(last_response.status).must_equal 404
      _(LockedCV::Attachment.where(id: attachment.id).first).wont_be_nil
      _(File.file?(storage_path_for(attachment.route))).must_equal true
    end
  end

  describe 'GET /api/v1/attachments/:attachment_id' do
    it 'HAPPY: gets one attachment' do
      attachment = @attachments.first

      get "/api/v1/attachments/#{attachment.id}", {}, auth_header(@account)

      _(last_response.status).must_equal 200
      _(json_body.dig('data', 'type')).must_equal 'attachment'
      _(json_body.dig('data', 'attributes', 'id')).must_equal attachment.id
      _(json_body['policy']).must_equal(
        'can_view' => true,
        'can_view_masked' => true,
        'can_access' => true,
        'can_upload' => true,
        'can_delete' => true,
        'role' => 'owner'
      )
    end

    it 'SECURITY: allows reads from read-only tokens but removes write capabilities' do
      attachment = @attachments.first
      read_only = LockedCV::AuthScope.new(LockedCV::AuthScope::READ_ONLY)

      get "/api/v1/attachments/#{attachment.id}", {}, auth_header(@account, scope: read_only)

      _(last_response.status).must_equal 200
      _(json_body['policy']).must_equal(
        'can_view' => true,
        'can_view_masked' => true,
        'can_access' => true,
        'can_upload' => false,
        'can_delete' => false,
        'role' => 'owner'
      )
    end

    it 'SAD: returns 404 for missing attachment' do
      get '/api/v1/attachments/999999', {}, auth_header(@account)

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Attachment not found')
    end

    it 'SAD_AUTH: returns 401 without bearer token' do
      attachment = @attachments.first

      get "/api/v1/attachments/#{attachment.id}"

      _(last_response.status).must_equal 401
      _(json_body).must_equal('message' => 'Missing authorization token')
    end

    it 'SECURITY: returns 404 when attachment belongs to another account' do
      other_account = LockedCV::CreateAccountService.call(
        account_data: DATA[:accounts].last.transform_keys(&:to_sym)
      )
      attachment = @attachments.first

      get "/api/v1/attachments/#{attachment.id}", {}, auth_header(other_account)

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Attachment not found')
    end

    it 'SECURITY: rejects SQL injection in attachment_id when fetching attachment' do
      injected_attachment_id = CGI.escape("#{@attachments.first.id}' OR '1'='1")

      get "/api/v1/attachments/#{injected_attachment_id}", {}, auth_header(@account)

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Attachment not found')
    end
  end

  describe 'GET /api/v1/attachments/:attachment_id/masked_text' do
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

      get "/api/v1/attachments/#{attachment.id}/masked_text", {}, auth_header(@account)

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

      post '/api/v1/attachments/upload', { file: upload }, auth_header(@account)
      attachment_id = json_body.dig('data', 'data', 'attributes', 'id')
      LockedCV::CreateSensitiveDataService.call(
        account_id: @account.id,
        attachment_id:,
        sensitive_data: DATA[:sensitive_data].first.transform_keys(&:to_sym)
      )

      get "/api/v1/attachments/#{attachment_id}/masked_text", {}, auth_header(@account)

      _(last_response.status).must_equal 200
      _(json_body['data']['attributes']['masked_text']).must_include '[FIRST_NAME]'
      _(json_body['data']['attributes']['masked_text']).must_include '[EMAIL]'
      _(json_body['data']['attributes']['masked_text']).must_include '[PHONE_NUMBER]'
    ensure
      pdf&.close!
    end

    it 'SAD: returns 404 when masking a missing attachment' do
      get '/api/v1/attachments/999999/masked_text', {}, auth_header(@account)

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Attachment not found')
    end
  end

  describe 'POST /api/v1/attachments/:attachment_id/masked_attachments' do
    it 'HAPPY: exports a visual-masked text-based PDF attachment record' do
      upload = Rack::Test::UploadedFile.new(
        'spec/fixtures/files/fake_resume_alan.pdf',
        'application/pdf',
        true,
        original_filename: 'fake_resume_alan.pdf'
      )

      post '/api/v1/attachments/upload', { file: upload }, auth_header(@account)
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

      python_bin = available_pdf_processor_python
      skip 'pdfplumber/reportlab Python dependencies are not available' unless python_bin

      with_python_bin(python_bin) do
        post(
          "/api/v1/attachments/#{attachment_id}/masked_attachments",
          nil,
          auth_header(@account)
        )
      end

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

    it 'HAPPY: previews a selected-label masked PDF without creating records' do
      attachment_id = upload_fake_resume_with_sensitive_data
      python_bin = available_pdf_processor_python
      skip 'pdfplumber/reportlab Python dependencies are not available' unless python_bin

      with_python_bin(python_bin) do
        post(
          "/api/v1/attachments/#{attachment_id}/masked_attachments/preview",
          { selected_labels: ['email'] }.to_json,
          auth_req_header(@account)
        )
      end

      _(last_response.status).must_equal 200
      _(last_response.content_type).must_equal 'application/pdf'
      _(last_response.headers['Content-Disposition']).must_equal 'inline; filename="masked_preview.pdf"'
      _(last_response.body.byteslice(0, 4)).must_equal '%PDF'
      _(LockedCV::MaskedAttachment.count).must_equal 0
      _(LockedCV::MaskedItem.count).must_equal 0

      preview_path = File.join('tmp', 'masked_previews', 'api_preview_selected_email.pdf')
      File.binwrite(preview_path, last_response.body)
      preview_text = LockedCV::ExtractPdf.text(preview_path)
      _(preview_text).wont_include 'alan@example.com'
      _(preview_text).must_include '0912-000-002'
      _(preview_text).must_include 'B987654321'
    ensure
      FileUtils.rm_f(preview_path) if defined?(preview_path) && preview_path
    end

    it 'SAD: rejects invalid preview selected labels' do
      post(
        "/api/v1/attachments/#{@attachments.first.id}/masked_attachments/preview",
        { selected_labels: ['unknown'] }.to_json,
        auth_req_header(@account)
      )

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Invalid selected labels')
    end

    it 'SECURITY: rejects masked PDF previews from viewer_masked accounts' do
      attachment_id = upload_fake_resume_with_sensitive_data
      viewer = viewer_masked_account_for(attachment_id)

      post(
        "/api/v1/attachments/#{attachment_id}/masked_attachments/preview",
        { selected_labels: ['email'] }.to_json,
        auth_req_header(viewer)
      )

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Attachment not found')
    end

    it 'HAPPY: creates records only for selected masked labels' do
      attachment_id = upload_fake_resume_with_sensitive_data
      python_bin = available_pdf_processor_python
      skip 'pdfplumber/reportlab Python dependencies are not available' unless python_bin

      with_python_bin(python_bin) do
        post(
          "/api/v1/attachments/#{attachment_id}/masked_attachments",
          { selected_labels: %w[email tel] }.to_json,
          auth_req_header(@account)
        )
      end

      _(last_response.status).must_equal 201
      masked_attachment_id = json_body.dig('data', 'data', 'attributes', 'id')
      _(last_response.headers['Location']).must_equal(
        "api/v1/attachments/#{attachment_id}/masked_attachments/#{masked_attachment_id}"
      )
      _(LockedCV::MaskedAttachment.count).must_equal 1
      _(LockedCV::MaskedItem.order(:field_name).map(&:field_name)).must_equal %w[email phone_number]
      masked_text = LockedCV::ExtractPdf.text(storage_path_for(json_body.dig('data', 'data', 'attributes', 'route')))
      _(masked_text).wont_include 'alan@example.com'
      _(masked_text).wont_include '0912-000-002'
      _(masked_text).must_include 'B987654321'
    end

    it 'SECURITY: rejects masked PDF exports from viewer_masked accounts' do
      attachment_id = upload_fake_resume_with_sensitive_data
      viewer = viewer_masked_account_for(attachment_id)

      post(
        "/api/v1/attachments/#{attachment_id}/masked_attachments",
        { selected_labels: ['email'] }.to_json,
        auth_req_header(viewer)
      )

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Attachment not found')
    end

    it 'HAPPY: downloads a saved masked PDF' do
      attachment_id = upload_fake_resume_with_sensitive_data
      python_bin = available_pdf_processor_python
      skip 'pdfplumber/reportlab Python dependencies are not available' unless python_bin

      with_python_bin(python_bin) do
        post(
          "/api/v1/attachments/#{attachment_id}/masked_attachments",
          { selected_labels: ['email'] }.to_json,
          auth_req_header(@account)
        )
      end
      masked_attachment_id = json_body.dig('data', 'data', 'attributes', 'id')

      get(
        "/api/v1/attachments/#{attachment_id}/masked_attachments/#{masked_attachment_id}/download",
        {},
        auth_header(@account)
      )

      _(last_response.status).must_equal 200
      _(last_response.content_type).must_equal 'application/pdf'
      _(last_response.headers['Content-Disposition']).must_equal 'attachment; filename="masked_fake_resume_alan.pdf"'
      _(last_response.body.byteslice(0, 4)).must_equal '%PDF'
    end

    it 'HAPPY: lets viewer_masked accounts download a saved masked PDF' do
      attachment_id, masked_attachment_id = create_masked_attachment_with_selected_labels(['email'])
      viewer = viewer_masked_account_for(attachment_id)

      get(
        "/api/v1/attachments/#{attachment_id}/masked_attachments/#{masked_attachment_id}/download",
        {},
        auth_header(viewer)
      )

      _(last_response.status).must_equal 200
      _(last_response.content_type).must_equal 'application/pdf'
      _(last_response.body.byteslice(0, 4)).must_equal '%PDF'
    end

    it 'HAPPY: downloads a password-protected masked PDF' do
      skip 'qpdf is not available' unless command_available?('qpdf')
      skip 'pdftotext is not available' unless command_available?('pdftotext')

      attachment_id, masked_attachment_id = create_masked_attachment_with_selected_labels(['email'])
      encrypted_files_before = Dir.glob(File.join('tmp', 'encrypted_pdfs', '*.pdf'))

      post(
        "/api/v1/attachments/#{attachment_id}/masked_attachments/#{masked_attachment_id}/encrypted_download",
        { password: 'test123' }.to_json,
        auth_req_header(@account)
      )

      _(last_response.status).must_equal 200
      _(last_response.content_type).must_equal 'application/pdf'
      _(last_response.headers['Content-Disposition']).must_equal(
        'attachment; filename="encrypted_masked_fake_resume_alan.pdf"'
      )
      _(last_response.body.byteslice(0, 4)).must_equal '%PDF'

      encrypted_path = File.join('tmp', 'encrypted_download_test.pdf')
      File.binwrite(encrypted_path, last_response.body)
      _stdout, _stderr, no_password_status = Open3.capture3('pdftotext', encrypted_path, '-')
      unlocked_text, _stderr, password_status = Open3.capture3('pdftotext', '-upw', 'test123', encrypted_path, '-')

      _(no_password_status.success?).must_equal false
      _(password_status.success?).must_equal true
      _(unlocked_text).must_include 'Alan Turing'
      _(Dir.glob(File.join('tmp', 'encrypted_pdfs', '*.pdf'))).must_equal encrypted_files_before
    ensure
      FileUtils.rm_f(encrypted_path) if defined?(encrypted_path) && encrypted_path
    end

    it 'HAPPY: lets viewer_masked accounts download a password-protected masked PDF' do
      skip 'qpdf is not available' unless command_available?('qpdf')
      skip 'pdftotext is not available' unless command_available?('pdftotext')

      attachment_id, masked_attachment_id = create_masked_attachment_with_selected_labels(['email'])
      viewer = viewer_masked_account_for(attachment_id)
      encrypted_files_before = Dir.glob(File.join('tmp', 'encrypted_pdfs', '*.pdf'))

      post(
        "/api/v1/attachments/#{attachment_id}/masked_attachments/#{masked_attachment_id}/encrypted_download",
        { password: 'test123' }.to_json,
        auth_req_header(viewer)
      )

      _(last_response.status).must_equal 200
      _(last_response.content_type).must_equal 'application/pdf'
      _(last_response.body.byteslice(0, 4)).must_equal '%PDF'

      encrypted_path = File.join('tmp', 'encrypted_download_viewer_masked_test.pdf')
      File.binwrite(encrypted_path, last_response.body)
      _stdout, _stderr, no_password_status = Open3.capture3('pdftotext', encrypted_path, '-')
      unlocked_text, _stderr, password_status = Open3.capture3('pdftotext', '-upw', 'test123', encrypted_path, '-')

      _(no_password_status.success?).must_equal false
      _(password_status.success?).must_equal true
      _(unlocked_text).must_include 'Alan Turing'
      _(Dir.glob(File.join('tmp', 'encrypted_pdfs', '*.pdf'))).must_equal encrypted_files_before
    ensure
      FileUtils.rm_f(encrypted_path) if defined?(encrypted_path) && encrypted_path
    end

    it 'HAPPY: lets owners create masked attachment share links' do
      attachment, masked_attachment = saved_masked_attachment_for

      create_masked_attachment_share_link(attachment, masked_attachment)

      _(last_response.status).must_equal 201
      _(json_body['message']).must_equal 'Masked attachment share link created'
      attributes = json_body.dig('data', 'attributes')
      _(json_body.dig('data', 'type')).must_equal 'masked_attachment_share_link'
      _(attributes['token']).wont_be_empty
      _(attributes['attachment_id']).must_equal attachment.id
      _(attributes['masked_attachment_id']).must_equal masked_attachment.id
      _(attributes['share_url']).must_equal "/share/masked-attachments/#{attributes['token']}"
      _(last_response.headers['Location']).must_equal "api/v1/masked_attachment_share_links/#{attributes['token']}"
    end

    it 'SECURITY: rejects masked attachment share link creation from viewer_masked accounts' do
      attachment, masked_attachment = saved_masked_attachment_for
      viewer = viewer_masked_account_for(attachment.id)

      create_masked_attachment_share_link(attachment, masked_attachment, viewer)

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Masked attachment not found')
    end

    it 'HAPPY: lets logged-in recipients redeem masked attachment share links' do
      attachment, masked_attachment = saved_masked_attachment_for
      recipient = recipient_account
      create_masked_attachment_share_link(attachment, masked_attachment)
      token = json_body.dig('data', 'attributes', 'token')

      post(
        "/api/v1/masked_attachment_share_links/#{token}/redeem",
        {}.to_json,
        auth_req_header(recipient)
      )

      _(last_response.status).must_equal 200
      _(json_body['message']).must_equal 'Masked attachment share link redeemed'
      _(json_body.dig('data', 'type')).must_equal 'masked_attachment_share_link_redemption'
      _(json_body.dig('data', 'attributes')).must_equal(
        'attachment_id' => attachment.id,
        'masked_attachment_id' => masked_attachment.id,
        'role' => 'viewer_masked'
      )
      _(LockedCV::AttachmentPermission.where(
        attachment_id: attachment.id,
        account_id: recipient.id,
        role: 'viewer_masked'
      ).count).must_equal 1
    end

    it 'HAPPY: redeems masked attachment share links idempotently' do
      attachment, masked_attachment = saved_masked_attachment_for
      recipient = recipient_account
      create_masked_attachment_share_link(attachment, masked_attachment)
      token = json_body.dig('data', 'attributes', 'token')

      2.times do
        post(
          "/api/v1/masked_attachment_share_links/#{token}/redeem",
          {}.to_json,
          auth_req_header(recipient)
        )

        _(last_response.status).must_equal 200
      end
      _(LockedCV::AttachmentPermission.where(
        attachment_id: attachment.id,
        account_id: recipient.id,
        role: 'viewer_masked'
      ).count).must_equal 1
    end

    it 'HAPPY: lets redeemed recipients download the shared masked PDF' do
      attachment, masked_attachment = saved_masked_attachment_for
      recipient = recipient_account
      create_masked_attachment_share_link(attachment, masked_attachment)
      token = json_body.dig('data', 'attributes', 'token')
      post("/api/v1/masked_attachment_share_links/#{token}/redeem", {}.to_json, auth_req_header(recipient))

      get(
        "/api/v1/attachments/#{attachment.id}/masked_attachments/#{masked_attachment.id}/download",
        {},
        auth_header(recipient)
      )

      _(last_response.status).must_equal 200
      _(last_response.content_type).must_equal 'application/pdf'
      _(last_response.body.byteslice(0, 4)).must_equal '%PDF'
    end

    it 'HAPPY: lets redeemed recipients download encrypted shared masked PDFs' do
      skip 'qpdf is not available' unless command_available?('qpdf')
      skip 'pdftotext is not available' unless command_available?('pdftotext')

      attachment, masked_attachment = saved_masked_attachment_for
      recipient = recipient_account
      create_masked_attachment_share_link(attachment, masked_attachment)
      token = json_body.dig('data', 'attributes', 'token')
      post("/api/v1/masked_attachment_share_links/#{token}/redeem", {}.to_json, auth_req_header(recipient))
      encrypted_files_before = Dir.glob(File.join('tmp', 'encrypted_pdfs', '*.pdf'))

      post(
        "/api/v1/attachments/#{attachment.id}/masked_attachments/#{masked_attachment.id}/encrypted_download",
        { password: 'test123' }.to_json,
        auth_req_header(recipient)
      )

      _(last_response.status).must_equal 200
      _(last_response.content_type).must_equal 'application/pdf'
      _(last_response.body.byteslice(0, 4)).must_equal '%PDF'

      encrypted_path = File.join('tmp', 'encrypted_shared_download_test.pdf')
      File.binwrite(encrypted_path, last_response.body)
      _stdout, _stderr, no_password_status = Open3.capture3('pdftotext', encrypted_path, '-')
      unlocked_text, _stderr, password_status = Open3.capture3('pdftotext', '-upw', 'test123', encrypted_path, '-')

      _(no_password_status.success?).must_equal false
      _(password_status.success?).must_equal true
      _(unlocked_text).must_include 'Alan Turing'
      _(Dir.glob(File.join('tmp', 'encrypted_pdfs', '*.pdf'))).must_equal encrypted_files_before
    ensure
      FileUtils.rm_f(encrypted_path) if defined?(encrypted_path) && encrypted_path
    end

    it 'SAD: returns 404 when redeeming an invalid masked attachment share link token' do
      recipient = recipient_account

      post(
        '/api/v1/masked_attachment_share_links/not-a-real-token/redeem',
        {}.to_json,
        auth_req_header(recipient)
      )

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Masked attachment share link not found')
    end

    it 'SAD: rejects encrypted download with a blank password' do
      attachment_id, masked_attachment_id = create_masked_attachment_with_selected_labels(['email'])

      post(
        "/api/v1/attachments/#{attachment_id}/masked_attachments/#{masked_attachment_id}/encrypted_download",
        { password: '   ' }.to_json,
        auth_req_header(@account)
      )

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Could not encrypt masked attachment')
    end

    it 'SAD: rejects encrypted download with invalid JSON' do
      attachment_id, masked_attachment_id = create_masked_attachment_with_selected_labels(['email'])

      post(
        "/api/v1/attachments/#{attachment_id}/masked_attachments/#{masked_attachment_id}/encrypted_download",
        '{',
        auth_req_header(@account)
      )

      _(last_response.status).must_equal 400
      _(json_body).must_equal('message' => 'Could not encrypt masked attachment')
    end

    it 'SAD: returns 404 when encrypted download masked attachment is missing' do
      attachment_id = upload_fake_resume_with_sensitive_data

      post(
        "/api/v1/attachments/#{attachment_id}/masked_attachments/999999/encrypted_download",
        { password: 'test123' }.to_json,
        auth_req_header(@account)
      )

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Masked attachment not found')
    end

    it 'SAD: returns 404 when exporting a missing attachment' do
      post '/api/v1/attachments/999999/masked_attachments', nil, auth_header(@account)

      _(last_response.status).must_equal 404
      _(json_body).must_equal('message' => 'Attachment not found')
    end
  end
end
