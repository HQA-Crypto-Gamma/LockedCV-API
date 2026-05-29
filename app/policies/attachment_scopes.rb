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
        return scope.none unless current_account

        shared_attachment_ids = AttachmentPermission
                                .where(account_id: current_account.id, role: 'viewer_masked')
                                .select(:attachment_id)

        scope.where(
          Sequel.|(
            { account_id: current_account.id },
            { id: shared_attachment_ids }
          )
        )
      end
    end
  end
end
