# frozen_string_literal: true

ENV['RACK_ENV'] ||= 'test'

require 'fileutils'
require 'securerandom'
require_relative '../require_app'

require_app

FIXTURE_PATH = 'spec/fixtures/files/fake_resume_alan.pdf'
ARTIFACT_PATH = 'spec/fixtures/generated/alan_system_masked_pdfplumber.pdf'
SENSITIVE_VALUES = [
  'Alan Turing',
  'alan@example.com',
  '0912-000-002',
  'B987654321'
].freeze
SENSITIVE_DATA = {
  first_name: 'Alan',
  last_name: 'Turing',
  phone_number: '0912-000-002',
  birthday: '1912-06-23',
  email: 'alan@example.com',
  address: 'Manchester',
  identification_numbers: 'B987654321'
}.freeze

def ensure_python_bin
  return if ENV['PYTHON_BIN']

  candidate = '/tmp/lockedcv-pdfspike-venv/bin/python'
  ENV['PYTHON_BIN'] = candidate if File.executable?(candidate)
end

def create_review_account
  suffix = SecureRandom.hex(8)
  LockedCV::CreateAccountService.call(
    account_data: {
      username: "pdf_review_#{suffix}",
      email: "pdf-review-#{suffix}@example.com",
      phone_number: "09#{rand(10_000_000..99_999_999)}",
      password: 'review-password'
    }
  )
end

def store_fixture(account)
  File.open(FIXTURE_PATH, 'rb') do |pdf|
    LockedCV::StoreAttachmentFile.call(
      uploaded_file: {
        filename: 'fake_resume_alan.pdf',
        type: 'application/pdf',
        tempfile: pdf
      },
      account_id: account.id
    )
  end
end

def create_attachment(account, route)
  LockedCV::CreateAttachmentService.call(
    account_id: account.id,
    attachment_data: {
      attachment_name: 'fake_resume_alan.pdf',
      route:
    }
  )
end

def create_sensitive_data(account, attachment)
  LockedCV::CreateSensitiveDataService.call(
    account_id: account.id,
    attachment_id: attachment.id,
    sensitive_data: SENSITIVE_DATA
  )
end

def print_text_layer_check
  text = LockedCV::ExtractPdf.text(ARTIFACT_PATH)
  puts 'Text-layer check:'
  SENSITIVE_VALUES.each do |value|
    result = text.downcase.include?(value.downcase) ? 'FOUND' : 'not found'
    puts "  #{value}: #{result}"
  end
  puts "  NAME label: #{text.include?('NAME') ? 'FOUND' : 'not found'}"
  puts "  EMAIL label: #{text.include?('EMAIL') ? 'FOUND' : 'not found'}"
  puts "  TEL label: #{text.include?('TEL') ? 'FOUND' : 'not found'}"
  puts "  ID label: #{text.include?('ID') ? 'FOUND' : 'not found'}"
end

ensure_python_bin
FileUtils.mkdir_p(File.dirname(ARTIFACT_PATH))

account = create_review_account
route = store_fixture(account)
attachment = create_attachment(account, route)
create_sensitive_data(account, attachment)

masked_attachment = LockedCV::ExportMaskedPdf.call(account_id: account.id, attachment_id: attachment.id)
masked_path = LockedCV::ResolveAttachmentPath.call(route: masked_attachment.route)
FileUtils.cp(masked_path, ARTIFACT_PATH)

puts "Generated artifact: #{ARTIFACT_PATH}"
puts "Source masked storage route: #{masked_attachment.route}"
puts "Masked attachment record id: #{masked_attachment.id}"
puts "Masked item records: #{masked_attachment.masked_items.count}"
print_text_layer_check
