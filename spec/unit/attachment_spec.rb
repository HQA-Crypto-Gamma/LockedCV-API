# frozen_string_literal: true

require_relative '../spec_helper'

describe LockedCV::Attachment do
  include LockedCV::SpecHelpers

  before do
    reset_database!
    @account = LockedCV::Account.create(DATA[:accounts].first.transform_keys(&:to_sym))
  end

  it 'HAPPY: creates an attachment associated with an account' do
    payload = DATA[:attachments].first.transform_keys(&:to_sym)

    attachment = @account.add_attachment(payload)

    _(attachment).wont_be_nil
    _(attachment.account_id).must_equal @account.id
    _(attachment.attachment_name).must_equal payload[:attachment_name]
    _(attachment.route).must_equal payload[:route]
    _(attachment.account.id).must_equal @account.id
  end

  it 'SECURITY: rejects mass assignment for account_id' do
    payload = DATA[:attachments].first.merge('account_id' => 'forged-account')

    error = _(
      proc { LockedCV::Attachment.new(payload) }
    ).must_raise Sequel::MassAssignmentRestriction

    _(error.message).must_include 'account_id'
  end

  it 'HAPPY: destroys dependent sensitive data when attachment is destroyed' do
    attachment = @account.add_attachment(DATA[:attachments].first.transform_keys(&:to_sym))
    sensitive_payload = DATA[:sensitive_data].first.transform_keys(&:to_sym)
    sensitive_data = LockedCV::SensitiveData.new(sensitive_payload)
    sensitive_data.attachment_id = attachment.id
    sensitive_data.save_changes

    before_count = LockedCV::SensitiveData.count

    attachment.destroy

    _(LockedCV::SensitiveData.count).must_equal(before_count - 1)
    _(LockedCV::SensitiveData.where(id: sensitive_data.id).first).must_be_nil
  end

  it 'HAPPY: supports masked attachment and masked item associations' do
    attachment = @account.add_attachment(DATA[:attachments].first.transform_keys(&:to_sym))
    masked_attachment = attachment.add_masked_attachment(
      attachment_name: 'masked_resume.pdf',
      route: "accounts/#{@account.id}/masked/masked_resume.pdf"
    )
    masked_item = masked_attachment.add_masked_item(
      field_name: 'email',
      value: 'alice.chen@example.com',
      source: 'sensitive_data',
      is_masked: true
    )

    _(attachment.masked_attachments.map(&:id)).must_include masked_attachment.id
    _(masked_attachment.attachment.id).must_equal attachment.id
    _(masked_attachment.masked_items.map(&:id)).must_include masked_item.id
    _(masked_item.masked_attachment.id).must_equal masked_attachment.id
  end

  it 'SECURITY: stores masked item values encrypted and validates source' do
    attachment = @account.add_attachment(DATA[:attachments].first.transform_keys(&:to_sym))
    masked_attachment = attachment.add_masked_attachment(
      attachment_name: 'masked_resume.pdf',
      route: "accounts/#{@account.id}/masked/masked_resume.pdf"
    )

    %w[sensitive_data regex manual].each do |source|
      masked_attachment.add_masked_item(
        field_name: 'email',
        value: "#{source}@example.com",
        source:,
        is_masked: true
      )
    end
    stored_row = db[:masked_items].where(source: 'sensitive_data').first

    _(stored_row[:value_secure]).wont_equal 'sensitive_data@example.com'
    _(LockedCV::MaskedItem.first(source: 'sensitive_data').value).must_equal 'sensitive_data@example.com'
    _(proc do
      masked_attachment.add_masked_item(
        field_name: 'email',
        value: 'bad@example.com',
        source: 'unsupported',
        is_masked: true
      )
    end).must_raise Sequel::ValidationFailed
  end

  it 'HAPPY: provides resource-role style helpers on attachment' do
    owner_account = LockedCV::Account.create(DATA[:accounts].last.transform_keys(&:to_sym))
    owner_role = LockedCV::Role.create(name: 'owner')
    masked_role = LockedCV::Role.create(name: 'viewer_masked')

    @account.add_system_role(masked_role)
    owner_account.add_system_role(owner_role)
    attachment = @account.add_attachment(DATA[:attachments].first.transform_keys(&:to_sym))

    _(attachment.owner.id).must_equal owner_account.id
    _(attachment.viewers_masked.map(&:id)).must_include @account.id
  end
end
