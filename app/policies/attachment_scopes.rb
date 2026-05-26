# frozen_string_literal: true

module LockedCV
  class AttachmentPolicy
    # Filters attachments to those the current account can access.
    # Re-expresses AttachmentPolicy#access? as a query for index routes.
    class AccountScope
      attr_reader :current_account, :scope

      def initialize(current_account, scope = Attachment.dataset)
        @current_account = current_account
        @scope = scope
      end

      def viewable
        scope.where(account_id: current_account&.id)
      end
    end
  end
end
