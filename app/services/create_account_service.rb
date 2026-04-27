# frozen_string_literal: true

module LockedCV
  # Creates an account from API payload.
  class CreateAccountService
    def self.call(account_data:)
      Account.create(account_data)
    end
  end
end
