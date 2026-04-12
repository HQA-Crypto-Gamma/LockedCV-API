# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:sensitive_data) do
      String :id, primary_key: true
      String :user_name
      String :phone_number
      Date :birthday
      String :email
      String :address
      String :identification_numbers
      foreign_key :file_id, :files

      unique %i[file_id]
    end
  end
end
