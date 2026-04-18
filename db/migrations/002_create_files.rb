# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:files) do
      uuid :id, primary_key: true

      String :file_name
      String :route

      DateTime :created_at
      DateTime :updated_at

      uuid :user_id, foreign_key: :users

      unique %i[user_id file_name]
    end
  end
end
