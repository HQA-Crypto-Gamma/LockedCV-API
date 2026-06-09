# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:masked_attachment_permissions) do
      primary_key :id

      foreign_key :attachment_id, :attachments, null: false
      foreign_key :masked_attachment_id, :masked_attachments, null: false
      uuid :account_id, foreign_key: :accounts, null: false
      String :role, null: false

      DateTime :created_at
      DateTime :updated_at

      unique %i[masked_attachment_id account_id role]
      index :attachment_id
      index :account_id
    end
  end
end
