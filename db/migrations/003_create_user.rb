# frozen_string_literal: true

# cause others have FK, we build this table.
Sequel.migration do
  change do
    create_table(:users) do
      primary_key :id

      String :first_name
      String :last_name
      String :phone_number

      DateTime :created_at
      DateTime :updated_at
    end
  end
end
