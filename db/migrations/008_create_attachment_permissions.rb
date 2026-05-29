# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:attachment_permissions) do
      primary_key :id

      foreign_key :attachment_id, :attachments, null: false
      uuid :account_id, foreign_key: :accounts, null: false
      String :role, null: false

      DateTime :created_at
      DateTime :updated_at

      unique %i[attachment_id account_id role]
    end
  end
end
