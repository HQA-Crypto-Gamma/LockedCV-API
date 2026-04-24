# frozen_string_literal: true

require_relative '../spec_helper'

describe LockedCV::Attachment do
  include LockedCV::SpecHelpers

  before do
    reset_database!
    @user = LockedCV::User.create(DATA[:users].first.transform_keys(&:to_sym))
  end

  it 'HAPPY: creates an attachment associated with a user' do
    payload = DATA[:attachments].first.transform_keys(&:to_sym)

    attachment = @user.add_attachment(payload)

    _(attachment).wont_be_nil
    _(attachment.user_id).must_equal @user.id
    _(attachment.attachment_name).must_equal payload[:attachment_name]
    _(attachment.route).must_equal payload[:route]
    _(attachment.user.id).must_equal @user.id
  end

  it 'SECURITY: rejects mass assignment for user_id' do
    payload = DATA[:attachments].first.merge('user_id' => 'forged-user')

    error = _(
      proc { LockedCV::Attachment.new(payload) }
    ).must_raise Sequel::MassAssignmentRestriction

    _(error.message).must_include 'user_id'
  end

  it 'HAPPY: destroys dependent sensitive data when attachment is destroyed' do
    attachment = @user.add_attachment(DATA[:attachments].first.transform_keys(&:to_sym))
    sensitive_payload = DATA[:sensitive_data].first.transform_keys(&:to_sym)
    sensitive_data = LockedCV::SensitiveData.new(sensitive_payload)
    sensitive_data.attachment_id = attachment.id
    sensitive_data.save_changes

    before_count = LockedCV::SensitiveData.count

    attachment.destroy

    _(LockedCV::SensitiveData.count).must_equal(before_count - 1)
    _(LockedCV::SensitiveData.where(id: sensitive_data.id).first).must_be_nil
  end
end
