# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:masked_attachments) do
      primary_key :id

      foreign_key :attachment_id, :attachments, null: false
      String :attachment_name, null: false
      String :route, null: false, unique: true

      DateTime :created_at
      DateTime :updated_at
    end
  end
end
