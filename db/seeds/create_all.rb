# frozen_string_literal: true

require 'date'
require 'yaml'

module LockedCV
  # Seeds local development data for manual API testing.
  module SeedData
    DIR = __dir__
    ROLES_INFO = YAML.safe_load_file("#{DIR}/role_seeds.yml").freeze
    ACCOUNTS_INFO = YAML.safe_load_file("#{DIR}/account_seeds.yml").freeze
    ATTACHMENTS_INFO = YAML.safe_load_file("#{DIR}/attachment_seeds.yml").freeze
    SENSITIVE_DATA_INFO = YAML.safe_load_file(
      "#{DIR}/sensitive_data_seeds.yml",
      permitted_classes: [Date]
    ).freeze

    SYSTEM_ROLE_ASSIGNMENTS = {
      'ada-lovelace' => %w[admin],
      'alan-turing' => %w[member]
    }.freeze

    module_function

    def run
      puts 'Seeding roles, accounts, attachments, and sensitive data'
      validate_seed_counts
      create_roles
      create_accounts_with_documents
      assign_system_roles
    end

    def validate_seed_counts
      return if ACCOUNTS_INFO.length == ATTACHMENTS_INFO.length &&
                ACCOUNTS_INFO.length == SENSITIVE_DATA_INFO.length

      raise 'Seed data counts must match for accounts, attachments, and sensitive data'
    end

    def create_roles
      ROLES_INFO.each do |role_info|
        Role.find_or_create(role_info.transform_keys(&:to_sym))
      end
    end

    def create_accounts_with_documents
      ACCOUNTS_INFO.each_with_index do |account_info, index|
        account = find_or_create_account(account_info)
        attachment = find_or_create_attachment(account, ATTACHMENTS_INFO[index])

        find_or_create_sensitive_data(account, attachment, SENSITIVE_DATA_INFO[index])
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
      SYSTEM_ROLE_ASSIGNMENTS.each do |username, role_names|
        account = Account.first(username:)
        role_names.each do |role_name|
          role = Role.first(name: role_name)
          account.add_system_role(role) unless account.system_roles_dataset.where(id: role.id).any?
        end
      end
    end
  end
end
