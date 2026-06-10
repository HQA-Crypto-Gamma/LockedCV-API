# frozen_string_literal: true

Sequel.migration do
  change do
    add_column :masked_attachment_permissions, :expires_at, DateTime
  end
end
