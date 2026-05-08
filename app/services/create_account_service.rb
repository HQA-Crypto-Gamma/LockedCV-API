# frozen_string_literal: true

module LockedCV
  # Creates an account from API payload.
  class CreateAccountService
    def self.call(account_data:)
      account = Account.create(account_data)
      account.add_system_role(default_member_role)
      account
    end

    def self.default_member_role
      Role.find_or_create(name: 'member')
    end
    private_class_method :default_member_role
  end
end
