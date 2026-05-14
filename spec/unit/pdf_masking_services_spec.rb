# frozen_string_literal: true

require 'tempfile'
require_relative '../spec_helper'

describe 'PDF Masking Services' do
  include LockedCV::SpecHelpers

  before do
    reset_database!
    reset_storage!
  end

  after do
    reset_storage!
  end

  it 'HAPPY: extracts text from a text-based PDF' do
    pdf = Tempfile.new(['lockedcv-text', '.pdf'])
    write_text_pdf(pdf.path, 'Email ada@example.com phone 0912-345-678')

    text = LockedCV::ExtractPdf.text(pdf.path)

    _(text).must_include 'ada@example.com'
    _(text).must_include '0912-345-678'
  ensure
    pdf&.close!
  end

  it 'HAPPY: extracts positioned text fragments from a text-based PDF' do
    pdf = Tempfile.new(['lockedcv-positioned-text', '.pdf'])
    write_text_pdf(pdf.path, 'Alice Chen alice.chen@example.com')

    fragments = LockedCV::ExtractPdf.positioned_text(pdf.path)

    fragment = fragments.find { |item| item[:text].include?('Alice Chen') }
    _(fragment).wont_be_nil
    _(fragment[:page_number]).must_equal 1
    _(fragment[:x]).must_be_kind_of Numeric
    _(fragment[:y]).must_be_kind_of Numeric
    _(fragment[:width]).must_be :>, 0
    _(fragment[:height]).must_be :>, 0
  ensure
    pdf&.close!
  end

  it 'HAPPY: detects supported sensitive data patterns' do
    text = 'Email ada@example.com phone 0912-345-678 born 1990-01-01 id A123456789'

    matches = LockedCV::DetectSensitiveData.call(text:)

    _(matches.map { |match| match[:type] }).must_equal %i[email phone_number birthday identification_number]
    _(matches.map { |match| match[:value] }).must_include 'ada@example.com'
    _(matches.map { |match| match[:value] }).must_include 'A123456789'
  end

  it 'HAPPY: masks stored sensitive data fields with stable labels' do
    text = 'Ada Lovelace lives in London. Email ada@example.com phone 0912-000-001 id A123456789.'
    sensitive_data = LockedCV::SensitiveData.new(DATA[:sensitive_data].first.transform_keys(&:to_sym))

    matches = LockedCV::MaskSensitiveText.matches_from_sensitive_data(text:, sensitive_data:)
    masked_text = LockedCV::MaskSensitiveText.call(text:, matches:)

    _(matches.map { |match| match[:type] }).must_include :first_name
    _(matches.map { |match| match[:type] }).must_include :address
    expected_text = '[FIRST_NAME] [LAST_NAME] lives in [ADDRESS]. ' \
                    'Email [EMAIL] phone [PHONE_NUMBER] id [IDENTIFICATION_NUMBERS].'
    _(masked_text).must_equal expected_text
  end

  it 'HAPPY: supplements masking with regex matches except dates' do
    text = 'Backup hr@example.com office 02-1234-5678 id B123456789 project 2024-05-07.'

    matches = LockedCV::MaskSensitiveText.matches_for_masking(text:, sensitive_data: nil)
    masked_text = LockedCV::MaskSensitiveText.call(text:, matches:)

    _(matches.map { |match| match[:type] }).must_equal %i[email phone_number identification_number]
    _(masked_text).must_equal 'Backup [EMAIL] office [PHONE_NUMBER] id [IDENTIFICATION_NUMBER] project 2024-05-07.'
  end

  it 'HAPPY: reads a fake resume and detects personal data without masking project dates by regex' do
    text = LockedCV::ExtractPdf.text('spec/fixtures/files/fake_resume_alan.pdf')

    matches = LockedCV::MaskSensitiveText.matches_for_masking(text:, sensitive_data: nil)

    _(text).must_include 'Alan Turing'
    _(text).must_include 'Jul 2025 - Aug 2025'
    _(text).must_include 'B987654321'
    _(matches.map { |match| match[:value] }).must_include 'alan@example.com'
    _(matches.map { |match| match[:value] }).must_include '0912-000-002'
    _(matches.map { |match| match[:value] }).wont_include 'Jul 2025'
  end

  it 'HAPPY: matches a name from SensitiveData without requiring a label' do
    text = LockedCV::ExtractPdf.text('spec/fixtures/files/fake_resume_alan.pdf')
    sensitive_data = LockedCV::SensitiveData.new(
      first_name: 'Alan',
      last_name: 'Turing',
      phone_number: '0912-000-002',
      birthday: '1912-06-23',
      email: 'alan@example.com',
      address: 'Manchester',
      identification_numbers: 'B987654321'
    )

    masked_text = LockedCV::MaskSensitiveText.call(text:, sensitive_data:)

    _(masked_text).must_include '[FIRST_NAME] [LAST_NAME]'
  end

  it 'HAPPY: processes an attachment into masked text' do
    account = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )
    pdf = Tempfile.new(['lockedcv-attachment', '.pdf'])
    write_text_pdf(pdf.path, 'Reach Ada Lovelace at ada@example.com, 0912-000-001, A123456789.')
    route = nil
    File.open(pdf.path, 'rb') do |uploaded_pdf|
      route = LockedCV::StoreAttachmentFile.call(
        uploaded_file: {
          filename: 'resume_ada.pdf',
          type: 'application/pdf',
          tempfile: uploaded_pdf
        },
        account_id: account.id
      )
    end
    attachment = LockedCV::CreateAttachmentService.call(
      account_id: account.id,
      attachment_data: {
        attachment_name: 'resume_ada.pdf',
        route:
      }
    )
    LockedCV::CreateSensitiveDataService.call(
      account_id: account.id,
      attachment_id: attachment.id,
      sensitive_data: DATA[:sensitive_data].first.transform_keys(&:to_sym)
    )

    result = LockedCV::ProcessAttachmentMasking.call(
      account_id: account.id,
      attachment_id: attachment.id
    )

    _(result[:attachment_id]).must_equal attachment.id
    _(result[:masked_text]).must_include '[FIRST_NAME]'
    _(result[:masked_text]).must_include '[LAST_NAME]'
    _(result[:masked_text]).must_include '[EMAIL]'
    _(result[:masked_text]).must_include '[PHONE_NUMBER]'
    _(result[:masked_text]).must_include '[IDENTIFICATION_NUMBERS]'
    _(result[:matches].map { |match| match[:type] }).must_include :email
  ensure
    pdf&.close!
  end

  it 'HAPPY: exports a visual-masked text-based PDF and records masked metadata' do
    account = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )
    route = LockedCV::StoreAttachmentFile.call(
      uploaded_file: {
        filename: 'fake_resume_alan.pdf',
        type: 'application/pdf',
        tempfile: File.open('spec/fixtures/files/fake_resume_alan.pdf', 'rb')
      },
      account_id: account.id
    )
    attachment = LockedCV::CreateAttachmentService.call(
      account_id: account.id,
      attachment_data: {
        attachment_name: 'fake_resume_alan.pdf',
        route:
      }
    )
    LockedCV::CreateSensitiveDataService.call(
      account_id: account.id,
      attachment_id: attachment.id,
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
    original_path = storage_path_for(route)

    masked_attachment = LockedCV::ExportMaskedPdf.call(account_id: account.id, attachment_id: attachment.id)

    _(masked_attachment.attachment_id).must_equal attachment.id
    _(masked_attachment.route).must_match %r{\Aaccounts/#{account.id}/masked/}
    _(masked_attachment.route).wont_match %r{\A/}
    _(File.file?(storage_path_for(masked_attachment.route))).must_equal true
    _(File.file?(original_path)).must_equal true
    _(masked_attachment.masked_items.map(&:source)).must_include 'sensitive_data'
    scrubbed_text = LockedCV::ExtractPdf.text(storage_path_for(masked_attachment.route))
    _(scrubbed_text).wont_include 'alan@example.com'
    _(scrubbed_text).wont_include '0912-000-002'
    _(scrubbed_text).wont_include 'B987654321'
  ensure
    route_file&.close if defined?(route_file)
  end

  it 'HAPPY: masks positioned text when sensitive values are not directly findable in PDF bytes' do
    account = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )
    pdf = Tempfile.new(['lockedcv-hex-text', '.pdf'])
    write_hex_text_pdf(pdf.path, 'Alan Turing alan@example.com 0912-000-002 B987654321')
    route = nil
    File.open(pdf.path, 'rb') do |uploaded_pdf|
      route = LockedCV::StoreAttachmentFile.call(
        uploaded_file: {
          filename: 'hex_resume.pdf',
          type: 'application/pdf',
          tempfile: uploaded_pdf
        },
        account_id: account.id
      )
    end
    attachment = LockedCV::CreateAttachmentService.call(
      account_id: account.id,
      attachment_data: {
        attachment_name: 'hex_resume.pdf',
        route:
      }
    )
    LockedCV::CreateSensitiveDataService.call(
      account_id: account.id,
      attachment_id: attachment.id,
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

    original_path = storage_path_for(route)
    _(LockedCV::ExtractPdf.text(original_path)).must_include 'alan@example.com'
    _(File.binread(original_path)).wont_include 'alan@example.com'
    masked_attachment = LockedCV::ExportMaskedPdf.call(account_id: account.id, attachment_id: attachment.id)
    masked_text = LockedCV::ExtractPdf.text(storage_path_for(masked_attachment.route))

    _(File.file?(storage_path_for(masked_attachment.route))).must_equal true
    _(File.file?(original_path)).must_equal true
    _(masked_text).wont_include 'alan@example.com'
    _(masked_text).wont_include '0912-000-002'
    _(masked_text).wont_include 'B987654321'
  ensure
    pdf&.close!
  end

  it 'HAPPY: masks realistic fake resume output without preserving extractable sensitive text' do
    account = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )
    source_path = 'spec/fixtures/files/fake_resume_alan.pdf'
    original_text = LockedCV::ExtractPdf.text(source_path)
    route = nil
    File.open(source_path, 'rb') do |uploaded_pdf|
      route = LockedCV::StoreAttachmentFile.call(
        uploaded_file: {
          filename: 'fake_resume_alan.pdf',
          type: 'application/pdf',
          tempfile: uploaded_pdf
        },
        account_id: account.id
      )
    end
    attachment = LockedCV::CreateAttachmentService.call(
      account_id: account.id,
      attachment_data: {
        attachment_name: 'fake_resume_alan.pdf',
        route:
      }
    )
    LockedCV::CreateSensitiveDataService.call(
      account_id: account.id,
      attachment_id: attachment.id,
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
    original_path = storage_path_for(route)

    masked_attachment = LockedCV::ExportMaskedPdf.call(account_id: account.id, attachment_id: attachment.id)
    masked_text = LockedCV::ExtractPdf.text(storage_path_for(masked_attachment.route))

    _(original_text).must_include 'alan@example.com'
    _(original_text).must_include '0912-000-002'
    _(original_text).must_include 'B987654321'
    _(File.file?(storage_path_for(masked_attachment.route))).must_equal true
    _(File.file?(original_path)).must_equal true
    _(masked_text).wont_include 'alan@example.com'
    _(masked_text).wont_include '0912-000-002'
    _(masked_text).wont_include 'B987654321'
  end

  it 'HAPPY: masks longer values before shorter names to avoid residual sensitive fragments' do
    account = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )
    source_path = 'spec/fixtures/files/fake_resume_alan.pdf'
    original_text = LockedCV::ExtractPdf.text(source_path)
    route = nil
    File.open(source_path, 'rb') do |uploaded_pdf|
      route = LockedCV::StoreAttachmentFile.call(
        uploaded_file: {
          filename: 'fake_resume_alan.pdf',
          type: 'application/pdf',
          tempfile: uploaded_pdf
        },
        account_id: account.id
      )
    end
    attachment = LockedCV::CreateAttachmentService.call(
      account_id: account.id,
      attachment_data: {
        attachment_name: 'fake_resume_alan.pdf',
        route:
      }
    )
    LockedCV::CreateSensitiveDataService.call(
      account_id: account.id,
      attachment_id: attachment.id,
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

    masked_attachment = LockedCV::ExportMaskedPdf.call(account_id: account.id, attachment_id: attachment.id)
    masked_text = LockedCV::ExtractPdf.text(storage_path_for(masked_attachment.route))

    _(original_text).must_include 'alan@example.com'
    _(original_text).must_include 'Alan Turing'
    _(original_text).must_include '0912-000-002'
    _(original_text).must_include 'B987654321'
    _(masked_text).wont_include 'Alan Turing'
    _(masked_text).wont_include 'alan@example.com'
    _(masked_text).wont_include '0912-000-002'
    _(masked_text).wont_include 'B987654321'
    _(masked_text).wont_include '@example.com'
    _(masked_text).wont_include '0912'
    _(masked_text).wont_include 'B987'
  end
end
