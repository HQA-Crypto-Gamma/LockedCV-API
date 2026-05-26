# frozen_string_literal: true

module LockedCV
  class AccountPolicy
    # Filters accounts to those the current account can list.
    class AdminScope
      attr_reader :current_account, :scope

      def initialize(current_account, scope = Account.dataset)
        @current_account = current_account
        @scope = scope
      end

      def viewable
        return scope if current_account&.admin?

        scope.where(id: current_account&.id)
      end
    end
  end
end
