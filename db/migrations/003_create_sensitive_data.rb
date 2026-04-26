# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:sensitive_data) do
      primary_key :id

      String :first_name_secure, null: false
      String :last_name_secure, null: false
      String :phone_number_secure, null: false
      String :birthday_secure, null: false
      String :email_secure, null: false
      String :address_secure, null: false
      String :identification_numbers_secure, null: false

      DateTime :created_at
      DateTime :updated_at

      foreign_key :attachment_id, :attachments

      unique %i[attachment_id]
    end
  end
end
