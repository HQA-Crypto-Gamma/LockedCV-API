# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:masked_attachment_share_links) do
      primary_key :id

      String :token, null: false, unique: true
      foreign_key :attachment_id, :attachments, null: false
      foreign_key :masked_attachment_id, :masked_attachments, null: false
      uuid :creator_account_id, foreign_key: :accounts, null: false
      DateTime :expires_at
      DateTime :revoked_at

      DateTime :created_at
      DateTime :updated_at

      index :attachment_id
      index :masked_attachment_id
      index :creator_account_id
    end
  end
end
