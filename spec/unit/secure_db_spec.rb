# frozen_string_literal: true

require_relative '../spec_helper'

describe LockedCV::SecureDB do
  include LockedCV::SpecHelpers

  before do
    reset_database!
  end

  it 'SECURITY: encrypts and decrypts database values' do
    plaintext = 'secret@example.com'

    ciphertext = LockedCV::SecureDB.encrypt(plaintext)

    _(ciphertext).wont_equal plaintext
    _(LockedCV::SecureDB.decrypt(ciphertext)).must_equal plaintext
  end

  it 'SECURITY: stores account personal data encrypted in the database' do
    payload = DATA[:accounts].first.transform_keys(&:to_sym)

    account = LockedCV::Account.create(payload)
    stored_row = db[:accounts].where(id: account.id).first

    _(stored_row[:first_name_secure]).wont_equal payload[:first_name]
    _(stored_row[:last_name_secure]).wont_equal payload[:last_name]
    _(stored_row[:phone_number_secure]).wont_equal payload[:phone_number]
    _(account.first_name).must_equal payload[:first_name]
    _(account.last_name).must_equal payload[:last_name]
    _(account.phone_number).must_equal payload[:phone_number]
  end
end
