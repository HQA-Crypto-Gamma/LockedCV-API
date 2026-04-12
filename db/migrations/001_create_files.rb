# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:files) do
      String :id, primary_key: true
      String :file_name
      String :route
      DateTime :update_time
      foreign_key :user_id, :users

      unique %i[user_id file_name]
    end
  end
end
