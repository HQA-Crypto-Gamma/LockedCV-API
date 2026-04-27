# frozen_string_literal: true

module LockedCV
  # Creates an attachment scoped to an account.
  class CreateAttachmentService
    class AccountNotFoundError < StandardError; end

    def self.call(account_id:, attachment_data:)
      account = FindAccountService.call(account_id:)
      raise AccountNotFoundError unless account

      account.add_attachment(attachment_data)
    end
  end
end
