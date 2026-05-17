# frozen_string_literal: true

module LockedCV
  # Lists accounts for admin-only settings views
  class ListAccountsService
    class NotAuthorizedError < StandardError; end

    def self.call(current_account:)
      raise NotAuthorizedError unless current_account&.admin?

      Account.order(:username).all
    end
  end
end
