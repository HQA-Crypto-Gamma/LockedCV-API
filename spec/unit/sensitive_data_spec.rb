# frozen_string_literal: true

require_relative '../spec_helper'

describe LockedCV::SensitiveData do
  include LockedCV::SpecHelpers

  before do
    reset_database!
    @account = LockedCV::Account.create(DATA[:accounts].first.transform_keys(&:to_sym))
    @attachment = @account.add_attachment(DATA[:attachments].first.transform_keys(&:to_sym))
  end

  it 'SECURITY: stores sensitive data encrypted in the database and decrypts through getters' do
    payload = DATA[:sensitive_data].first.transform_keys(&:to_sym)

    sensitive_data = LockedCV::SensitiveData.new(payload)
    sensitive_data.attachment_id = @attachment.id
    sensitive_data.save_changes
    stored_row = db[:sensitive_data].where(id: sensitive_data.id).first

    _(stored_row[:user_name_secure]).wont_equal payload[:user_name]
    _(stored_row[:phone_number_secure]).wont_equal payload[:phone_number]
    _(stored_row[:birthday_secure]).wont_equal payload[:birthday].to_s
    _(stored_row[:email_secure]).wont_equal payload[:email]
    _(stored_row[:address_secure]).wont_equal payload[:address]
    _(stored_row[:identification_numbers_secure]).wont_equal payload[:identification_numbers]
    _(sensitive_data.user_name).must_equal payload[:user_name]
    _(sensitive_data.phone_number).must_equal payload[:phone_number]
    _(sensitive_data.birthday).must_equal payload[:birthday].to_s
    _(sensitive_data.email).must_equal payload[:email]
    _(sensitive_data.address).must_equal payload[:address]
    _(sensitive_data.identification_numbers).must_equal payload[:identification_numbers]
  end

  it 'SECURITY: rejects mass assignment for attachment_id' do
    payload = DATA[:sensitive_data].first.merge('attachment_id' => 'forged-attachment')

    error = _(
      proc { LockedCV::SensitiveData.new(payload) }
    ).must_raise Sequel::MassAssignmentRestriction

    _(error.message).must_include 'attachment_id'
  end

  it 'HAPPY: belongs to its attachment' do
    payload = DATA[:sensitive_data].first.transform_keys(&:to_sym)

    sensitive_data = LockedCV::SensitiveData.new(payload)
    sensitive_data.attachment_id = @attachment.id
    sensitive_data.save_changes

    _(sensitive_data.attachment.id).must_equal @attachment.id
    _(sensitive_data.attachment.attachment_name).must_equal @attachment.attachment_name
  end
end
