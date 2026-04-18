# frozen_string_literal: true

# cause others have FK, we build this table.
Sequel.migration do
  change do
    create_table(:users) do
      uuid :id, primary_key: true

      String :first_name_secure
      String :last_name_secure
      String :phone_number_secure

      DateTime :created_at
      DateTime :updated_at
    end
  end
end
