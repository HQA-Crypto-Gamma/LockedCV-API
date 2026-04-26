# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:attachments) do
      primary_key :id

      String :attachment_name, null: false
      String :route, null: false, unique: true

      DateTime :created_at
      DateTime :updated_at

      uuid :account_id, foreign_key: :accounts

      unique %i[account_id attachment_name]
    end
  end
end
