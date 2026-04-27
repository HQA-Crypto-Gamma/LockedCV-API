# frozen_string_literal: true

module LockedCV
  # Finds a single account by id.
  class FindAccountService
    def self.call(account_id:)
      Account.first(id: account_id.to_s)
    end
  end
end
