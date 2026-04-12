# frozen_string_literal: true

# cause others have FK, we build this table.
Sequel.migration do
  change do
    create_table(:users) do
      String :id, primary_key: true
      String :first_name
      String :last_name
      String :phone_number
    end
  end
end
