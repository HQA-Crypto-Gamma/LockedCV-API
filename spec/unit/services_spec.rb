# frozen_string_literal: true

require 'tempfile'
require_relative '../spec_helper'

describe 'Service Objects' do
  include LockedCV::SpecHelpers

  before do
    reset_database!
  end

  after do
    reset_storage!
  end

  it 'HAPPY: creates and finds an account' do
    account = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )

    found = LockedCV::FindAccountService.call(account_id: account.id)

    _(found.id).must_equal account.id
  end

  it 'SAD: returns nil when finding a missing account' do
    found = LockedCV::FindAccountService.call(account_id: 'missing-account')

    _(found).must_be_nil
  end

  it 'HAPPY: authenticates an account with valid credentials' do
    payload = DATA[:accounts].first.transform_keys(&:to_sym)
    account = LockedCV::CreateAccountService.call(account_data: payload)

    authenticated = LockedCV::AuthenticateAccountService.call(
      username: payload[:username],
      password: payload[:password]
    )
    attributes = authenticated.dig(:data, :attributes)

    _(authenticated.dig(:data, :type)).must_equal 'authenticated_account'
    _(attributes[:id]).must_equal account.id
    _(attributes[:username]).must_equal account.username
    _(attributes[:email]).must_equal account.email
    _(attributes[:roles]).must_equal ['member']
    token_payload = LockedCV::AuthToken.load(attributes[:auth_token]).payload
    _(token_payload['account_id']).must_equal account.id
    _(token_payload['username']).must_equal account.username
    _(token_payload['email']).must_equal account.email
  end

  it 'SAD: raises when authenticating with an invalid password' do
    payload = DATA[:accounts].first.transform_keys(&:to_sym)
    LockedCV::CreateAccountService.call(account_data: payload)

    _(
      proc do
        LockedCV::AuthenticateAccountService.call(
          username: payload[:username],
          password: 'not-the-password'
        )
      end
    ).must_raise LockedCV::AuthenticateAccountService::UnauthorizedError
  end

  it 'SAD: raises when authenticating an unknown account' do
    _(
      proc do
        LockedCV::AuthenticateAccountService.call(
          username: 'missing-account',
          password: 'anything'
        )
      end
    ).must_raise LockedCV::AuthenticateAccountService::UnauthorizedError
  end

  it 'HAPPY: admin assigns a system role to an account' do
    admin_role = LockedCV::Role.create(name: 'admin')
    admin = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )
    target = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].last.transform_keys(&:to_sym)
    )
    admin.add_system_role(admin_role)

    result = LockedCV::AssignSystemRoleService.call(
      current_account: admin,
      target_username: target.username,
      role_name: admin_role.name
    )

    _(result.created?).must_equal true
    _(target.reload.system_roles.map(&:name)).must_equal ['admin']
  end

  it 'HAPPY: setting admin removes the default member system role' do
    admin_role = LockedCV::Role.create(name: 'admin')
    admin = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )
    target = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].last.transform_keys(&:to_sym)
    )
    admin.add_system_role(admin_role)

    LockedCV::AssignSystemRoleService.call(
      current_account: admin,
      target_username: target.username,
      role_name: 'admin'
    )

    _(target.reload.system_roles.map(&:name)).must_equal ['admin']
  end

  it 'HAPPY: assigning an already assigned system role is idempotent' do
    admin_role = LockedCV::Role.create(name: 'admin')
    admin = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )
    target = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].last.transform_keys(&:to_sym)
    )
    admin.add_system_role(admin_role)

    result = LockedCV::AssignSystemRoleService.call(
      current_account: admin,
      target_username: target.username,
      role_name: 'member'
    )

    _(result.created?).must_equal false
    _(target.reload.system_roles.count { |role| role.name == 'member' }).must_equal 1
  end

  it 'SAD: non-admin cannot assign a system role' do
    member = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )
    target = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].last.transform_keys(&:to_sym)
    )

    _(
      proc do
        LockedCV::AssignSystemRoleService.call(
          current_account: member,
          target_username: target.username,
          role_name: 'member'
        )
      end
    ).must_raise LockedCV::AssignSystemRoleService::NotAuthorizedError
  end

  it 'SECURITY: read-only admin scope cannot assign a system role' do
    admin_role = LockedCV::Role.create(name: 'admin')
    admin = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )
    target = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].last.transform_keys(&:to_sym)
    )
    admin.add_system_role(admin_role)
    read_only = LockedCV::AuthScope.new(LockedCV::AuthScope::READ_ONLY)

    _(
      proc do
        LockedCV::AssignSystemRoleService.call(
          current_account: admin,
          target_username: target.username,
          role_name: 'admin',
          auth_scope: read_only
        )
      end
    ).must_raise LockedCV::AssignSystemRoleService::NotAuthorizedError
  end

  it 'SECURITY: read-only scope cannot update an account' do
    account = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )
    read_only = LockedCV::AuthScope.new(LockedCV::AuthScope::READ_ONLY)

    _(
      proc do
        LockedCV::UpdateAccountService.call(
          current_account: account,
          account_data: { first_name: 'Ada' },
          auth_scope: read_only
        )
      end
    ).must_raise LockedCV::UpdateAccountService::NotAuthorizedError
  end

  it 'SECURITY: read-only scope cannot change a password' do
    payload = DATA[:accounts].first.transform_keys(&:to_sym)
    account = LockedCV::CreateAccountService.call(account_data: payload)
    read_only = LockedCV::AuthScope.new(LockedCV::AuthScope::READ_ONLY)

    _(
      proc do
        LockedCV::ChangePasswordService.call(
          current_account: account,
          password_data: { current_password: payload[:password], password: 'new-secret' },
          auth_scope: read_only
        )
      end
    ).must_raise LockedCV::ChangePasswordService::NotAuthorizedError
  end

  it 'SECURITY: read-only admin scope cannot delete an account' do
    admin_role = LockedCV::Role.create(name: 'admin')
    admin = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )
    target = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].last.transform_keys(&:to_sym)
    )
    admin.add_system_role(admin_role)
    read_only = LockedCV::AuthScope.new(LockedCV::AuthScope::READ_ONLY)

    _(
      proc do
        LockedCV::DeleteAccountService.call(
          current_account: admin,
          target_account_id: target.id,
          auth_scope: read_only
        )
      end
    ).must_raise LockedCV::DeleteAccountService::NotAuthorizedError
    _(LockedCV::Account.first(id: target.id)).wont_be_nil
  end

  it 'HAPPY: creates an attachment for an account' do
    account = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )

    attachment = LockedCV::CreateAttachmentService.call(
      account_id: account.id,
      attachment_data: DATA[:attachments].first.transform_keys(&:to_sym)
    )

    _(attachment.account_id).must_equal account.id
  end

  it 'SECURITY: read-only scope cannot upload an attachment' do
    account = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )
    pdf = Tempfile.new(['lockedcv-service-read-only-upload', '.pdf'])
    write_text_pdf(pdf.path, 'Uploaded PDF text')
    uploaded_file = { filename: 'resume.pdf', tempfile: pdf }
    read_only = LockedCV::AuthScope.new(LockedCV::AuthScope::READ_ONLY)

    _(
      proc do
        LockedCV::UploadAttachmentFile.call(
          current_account: account,
          uploaded_file:,
          auth_scope: read_only
        )
      end
    ).must_raise LockedCV::UploadAttachmentFile::NotAuthorizedError
  ensure
    pdf&.close!
  end

  it 'HAPPY: finds an attachment scoped to an account' do
    account = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )
    attachment = LockedCV::CreateAttachmentService.call(
      account_id: account.id,
      attachment_data: DATA[:attachments].first.transform_keys(&:to_sym)
    )

    found = LockedCV::FindAttachmentService.call(
      account_id: account.id,
      attachment_id: attachment.id
    )

    _(found.id).must_equal attachment.id
  end

  it 'SECURITY: read-only scope cannot delete an attachment' do
    account = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )
    attachment = LockedCV::CreateAttachmentService.call(
      account_id: account.id,
      attachment_data: DATA[:attachments].first.transform_keys(&:to_sym)
    )
    read_only = LockedCV::AuthScope.new(LockedCV::AuthScope::READ_ONLY)

    _(
      proc do
        LockedCV::DeleteAttachmentService.call(
          current_account: account,
          attachment_id: attachment.id,
          auth_scope: read_only
        )
      end
    ).must_raise LockedCV::DeleteAttachmentService::NotAuthorizedError
    _(LockedCV::Attachment.first(id: attachment.id)).wont_be_nil
  end

  it 'SAD: returns nil when attachment does not belong to account' do
    account = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )
    other_account = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].last.transform_keys(&:to_sym)
    )
    attachment = LockedCV::CreateAttachmentService.call(
      account_id: account.id,
      attachment_data: DATA[:attachments].first.transform_keys(&:to_sym)
    )

    found = LockedCV::FindAttachmentService.call(
      account_id: other_account.id,
      attachment_id: attachment.id
    )

    _(found).must_be_nil
  end

  it 'SAD: raises when creating an attachment for a missing account' do
    _(
      proc do
        LockedCV::CreateAttachmentService.call(
          account_id: 'missing-account',
          attachment_data: DATA[:attachments].first.transform_keys(&:to_sym)
        )
      end
    ).must_raise LockedCV::CreateAttachmentService::AccountNotFoundError
  end

  it 'HAPPY: creates sensitive data for an attachment' do
    account = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )
    attachment = LockedCV::CreateAttachmentService.call(
      account_id: account.id,
      attachment_data: DATA[:attachments].first.transform_keys(&:to_sym)
    )

    sensitive_data = LockedCV::CreateSensitiveDataService.call(
      account_id: account.id,
      attachment_id: attachment.id,
      sensitive_data: DATA[:sensitive_data].first.transform_keys(&:to_sym)
    )

    _(sensitive_data.attachment_id).must_equal attachment.id
  end

  it 'HAPPY: finds sensitive data by attachment' do
    account = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )
    attachment = LockedCV::CreateAttachmentService.call(
      account_id: account.id,
      attachment_data: DATA[:attachments].first.transform_keys(&:to_sym)
    )
    sensitive_data = LockedCV::CreateSensitiveDataService.call(
      account_id: account.id,
      attachment_id: attachment.id,
      sensitive_data: DATA[:sensitive_data].first.transform_keys(&:to_sym)
    )

    found = LockedCV::FindSensitiveDataService.call(attachment_id: attachment.id)

    _(found.id).must_equal sensitive_data.id
  end

  it 'SAD: raises when creating sensitive data for a missing attachment' do
    account = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )

    _(
      proc do
        LockedCV::CreateSensitiveDataService.call(
          account_id: account.id,
          attachment_id: 'missing-attachment',
          sensitive_data: DATA[:sensitive_data].first.transform_keys(&:to_sym)
        )
      end
    ).must_raise LockedCV::CreateSensitiveDataService::AttachmentNotFoundError
  end

  it 'SAD: raises when sensitive data already exists for an attachment' do
    account = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )
    attachment = LockedCV::CreateAttachmentService.call(
      account_id: account.id,
      attachment_data: DATA[:attachments].first.transform_keys(&:to_sym)
    )
    payload = DATA[:sensitive_data].first.transform_keys(&:to_sym)

    LockedCV::CreateSensitiveDataService.call(
      account_id: account.id,
      attachment_id: attachment.id,
      sensitive_data: payload
    )

    _(
      proc do
        LockedCV::CreateSensitiveDataService.call(
          account_id: account.id,
          attachment_id: attachment.id,
          sensitive_data: payload
        )
      end
    ).must_raise LockedCV::CreateSensitiveDataService::SensitiveDataExistsError
  end
end
