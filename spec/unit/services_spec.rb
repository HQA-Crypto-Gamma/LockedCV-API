# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Service Objects' do
  include LockedCV::SpecHelpers

  before do
    reset_database!
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
