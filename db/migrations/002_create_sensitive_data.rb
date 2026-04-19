# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:sensitive_data) do
      primary_key :id

      String :user_name
      String :phone_number
      Date :birthday
      String :email
      String :address
      String :identification_numbers

      DateTime :created_at
      DateTime :updated_at

      foreign_key :attachment_id, :attachments

      unique %i[attachment_id]
    end
  end
end
