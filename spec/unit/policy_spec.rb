# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Resource policies' do
  include LockedCV::SpecHelpers

  before do
    reset_database!
    @member_role = LockedCV::Role.create(name: 'member')
    @admin_role = LockedCV::Role.create(name: 'admin')

    @owner = create_account('ada-owner', 'ada-owner@example.com', '0912-100-001')
    @other = create_account('alan-other', 'alan-other@example.com', '0912-100-002')
    @admin = create_account('grace-admin', 'grace-admin@example.com', '0912-100-003')
    @owner.add_system_role(@member_role)
    @other.add_system_role(@member_role)
    @admin.add_system_role(@admin_role)

    @attachment = @owner.add_attachment(DATA[:attachments].first.transform_keys(&:to_sym))
    @sensitive_data = LockedCV::SensitiveData.new(DATA[:sensitive_data].first.transform_keys(&:to_sym))
    @sensitive_data.attachment_id = @attachment.id
    @sensitive_data.save_changes
  end

  it 'authorizes accounts by self and admin privileges' do
    owner_policy = LockedCV::AccountPolicy.new(@owner, @owner)
    admin_policy = LockedCV::AccountPolicy.new(@admin, @owner)
    other_policy = LockedCV::AccountPolicy.new(@other, @owner)

    _(owner_policy.view?).must_equal true
    _(owner_policy.update?).must_equal true
    _(owner_policy.delete?).must_equal false
    _(admin_policy.view?).must_equal true
    _(admin_policy.delete?).must_equal true
    _(admin_policy.assign_system_role?).must_equal true
    _(other_policy.view?).must_equal false
  end

  it 'summarizes account capabilities' do
    _(LockedCV::AccountPolicy.new(@admin).capabilities).must_equal(
      can_manage_accounts: true,
      can_manage_system_roles: true,
      can_upload_attachments: true
    )
    _(LockedCV::AccountPolicy.new(@owner).capabilities).must_equal(
      can_manage_accounts: false,
      can_manage_system_roles: false,
      can_upload_attachments: true
    )
  end

  it 'authorizes attachments by ownership' do
    owner_policy = LockedCV::AttachmentPolicy.new(@owner, @attachment)
    other_policy = LockedCV::AttachmentPolicy.new(@other, @attachment)

    _(owner_policy.owner?).must_equal true
    _(owner_policy.view?).must_equal true
    _(owner_policy.view_masked?).must_equal true
    _(owner_policy.access?).must_equal true
    _(owner_policy.delete?).must_equal true
    _(owner_policy.summary[:role]).must_equal 'owner'
    _(other_policy.view?).must_equal false
    _(other_policy.view_masked?).must_equal false
    _(other_policy.access?).must_equal false
    _(other_policy.delete?).must_equal false
  end

  it 'scopes attachments to the current account' do
    other_attachment = @other.add_attachment(DATA[:attachments].last.transform_keys(&:to_sym))

    viewable_ids = LockedCV::AttachmentPolicy::AccountScope.new(@owner).viewable.map(:id)

    _(viewable_ids).must_include @attachment.id
    _(viewable_ids).wont_include other_attachment.id
  end

  it 'authorizes sensitive data through its attachment policy' do
    owner_policy = LockedCV::SensitiveDataPolicy.new(@owner, @sensitive_data)
    other_policy = LockedCV::SensitiveDataPolicy.new(@other, @sensitive_data)

    _(owner_policy.view?).must_equal true
    _(owner_policy.update?).must_equal true
    _(owner_policy.delete?).must_equal true
    _(other_policy.view?).must_equal false
    _(other_policy.update?).must_equal false
    _(other_policy.delete?).must_equal false
  end

  it 'scopes sensitive data through viewable attachments' do
    other_attachment = @other.add_attachment(DATA[:attachments].last.transform_keys(&:to_sym))
    other_sensitive_data = LockedCV::SensitiveData.new(DATA[:sensitive_data].last.transform_keys(&:to_sym))
    other_sensitive_data.attachment_id = other_attachment.id
    other_sensitive_data.save_changes

    viewable_ids = LockedCV::SensitiveDataPolicy::AccountScope.new(@owner).viewable.map(:id)

    _(viewable_ids).must_include @sensitive_data.id
    _(viewable_ids).wont_include other_sensitive_data.id
  end

  private

  def create_account(username, email, phone_number)
    LockedCV::Account.create(
      username:,
      email:,
      phone_number:,
      password: 'secure-secret'
    )
  end
end
