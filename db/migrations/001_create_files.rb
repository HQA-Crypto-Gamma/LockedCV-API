# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:files) do
      primary_key :id

      String :file_name
      String :route

      DateTime :created_at
      DateTime :updated_at

      foreign_key :user_id, :users

      unique %i[user_id file_name]
    end
  end
end
