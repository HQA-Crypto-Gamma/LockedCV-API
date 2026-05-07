# frozen_string_literal: true

module LockedCV
  # Lists accounts for admin-only settings views
  class ListAccountsService
    class MissingCurrentAccountError < StandardError; end
    class NotAuthorizedError < StandardError; end

    def self.call(current_account_id:)
      raise MissingCurrentAccountError unless current_account_id

      current_account = Account.first(id: current_account_id)
      raise NotAuthorizedError unless current_account&.admin?

      Account.order(:username).all
    end
  end
end
