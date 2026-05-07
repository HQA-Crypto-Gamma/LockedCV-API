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

    text = LockedCV::ExtractPdfText.call(file_path: pdf.path)

    _(text).must_include 'ada@example.com'
    _(text).must_include '0912-345-678'
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
end
