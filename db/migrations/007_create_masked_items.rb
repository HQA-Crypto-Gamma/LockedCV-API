# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:masked_items) do
      primary_key :id

      foreign_key :masked_attachment_id, :masked_attachments, null: false
      String :field_name, null: false
      String :value_secure, null: false
      TrueClass :is_masked, null: false, default: true
      String :source, null: false

      DateTime :created_at
      DateTime :updated_at
    end
  end
end
