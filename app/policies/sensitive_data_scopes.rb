# frozen_string_literal: true

module LockedCV
  class SensitiveDataPolicy
    # Filters sensitive data through the current account's accessible attachments.
    class AccountScope
      attr_reader :current_account, :scope

      def initialize(current_account, scope = SensitiveData.dataset)
        @current_account = current_account
        @scope = scope
      end

      def viewable
        scope.where(attachment_id: AttachmentPolicy::AccountScope.new(current_account).viewable.select(:id))
      end
    end
  end
end
