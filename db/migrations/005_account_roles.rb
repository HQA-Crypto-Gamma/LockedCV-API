# frozen_string_literal: true

require 'sequel'

Sequel.migration do
  change do
    create_join_table(
      account_id: { table: :accounts, type: :uuid },
      role_id: :roles
    )
  end
end
