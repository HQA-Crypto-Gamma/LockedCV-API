# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:sensitive_data) do
      uuid :id, primary_key: true

      String :user_name_secure
      String :phone_number_secure
      String :birthday_secure
      String :email_secure
      String :address_secure
      String :identification_numbers_secure

      DateTime :created_at
      DateTime :updated_at

      uuid :file_id, foreign_key: :files

      unique %i[file_id]
    end
  end
end
