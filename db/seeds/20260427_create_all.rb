# frozen_string_literal: true

require 'date'
require 'yaml'

module LockedCV
  # Seeds local development data for manual API testing.
  module SeedData
    module_function

    def run
      puts 'Seeding roles, accounts, attachments, and sensitive data'
      validate_seed_counts
      create_roles
      create_accounts_with_documents
      assign_system_roles
    end

    def seed_dir
      __dir__
    end

    def roles_info
      YAML.safe_load_file("#{seed_dir}/role_seeds.yml")
    end

    def accounts_info
      YAML.safe_load_file("#{seed_dir}/account_seeds.yml")
    end

    def attachments_info
      YAML.safe_load_file("#{seed_dir}/attachment_seeds.yml")
    end

    def sensitive_data_info
      YAML.safe_load_file(
        "#{seed_dir}/sensitive_data_seeds.yml",
        permitted_classes: [Date]
      )
    end

    def system_role_assignments
      {
        'ada-lovelace' => %w[admin],
        'alan-turing' => %w[member]
      }
    end

    def validate_seed_counts
      return if accounts_info.length == attachments_info.length &&
                accounts_info.length == sensitive_data_info.length

      raise 'Seed data counts must match for accounts, attachments, and sensitive data'
    end

    def create_roles
      roles_info.each do |role_info|
        Role.find_or_create(role_info.transform_keys(&:to_sym))
      end
    end

    def create_accounts_with_documents
      accounts_info.each_with_index do |account_info, index|
        account = find_or_create_account(account_info)
        attachment = find_or_create_attachment(account, attachments_info[index])

        find_or_create_sensitive_data(account, attachment, sensitive_data_info[index])
      end
    end

    def find_or_create_account(account_info)
      Account.first(username: account_info['username']) ||
        CreateAccountService.call(account_data: account_info.transform_keys(&:to_sym))
    end

    def find_or_create_attachment(account, attachment_info)
      account.attachments_dataset.first(attachment_name: attachment_info['attachment_name']) ||
        CreateAttachmentService.call(
          account_id: account.id,
          attachment_data: attachment_info.transform_keys(&:to_sym)
        )
    end

    def find_or_create_sensitive_data(account, attachment, sensitive_data_info)
      SensitiveData.first(attachment_id: attachment.id) ||
        CreateSensitiveDataService.call(
          account_id: account.id,
          attachment_id: attachment.id,
          sensitive_data: sensitive_data_info.transform_keys(&:to_sym)
        )
    end

    def assign_system_roles
      system_role_assignments.each do |username, role_names|
        account = Account.first(username:)
        role_names.each do |role_name|
          role = Role.first(name: role_name)
          next if account.system_roles_dataset.where(id: role.id).any?

          account.add_system_role(role)
        end
      end
    end
  end
end

Sequel.seed(:development) do
  def run
    LockedCV::SeedData.run
  end
end
