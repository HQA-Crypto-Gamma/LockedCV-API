# frozen_string_literal: true

# cause others have FK, we build this table.
Sequel.migration do
  change do
    create_table(:accounts) do
      uuid :id, primary_key: true

      String :username, null: false, unique: true
      String :email_secure, null: false
      String :email_hash, null: false, unique: true
      String :password_digest, null: false
      String :phone_number_secure
      String :phone_number_hash, unique: true

      DateTime :created_at
      DateTime :updated_at
    end
  end
end
