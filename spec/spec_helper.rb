# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'minitest/rg'
require 'rack/test'
require 'yaml'

require_relative '../require_app'
require_app

module LockedCV
  # Shared helpers for spec setup/teardown and database seed loading
  module SpecHelpers
    USER_SEEDS_FILE = 'db/seeds/user_seeds.yml'
    FILE_SEEDS_FILE = 'db/seeds/file_seeds.yml'
    SENSITIVE_DATA_SEEDS_FILE = 'db/seeds/sensitive_data_seeds.yml'
    REQUIRED_TABLES = %i[users files sensitive_data].freeze

    def db
      LockedCV::Api.DB
    end

    def ensure_database_schema!
      missing_tables = REQUIRED_TABLES.reject { |table| db.table_exists?(table) }
      return if missing_tables.empty?

      raise "Missing tables: #{missing_tables.join(', ')}. Run `bundle exec rake db:migrate` first."
    end

    def seeded_users
      YAML.safe_load_file(USER_SEEDS_FILE)
    end

    def seeded_files
      YAML.safe_load_file(FILE_SEEDS_FILE)
    end

    def seeded_sensitive_data
      YAML.safe_load_file(SENSITIVE_DATA_SEEDS_FILE)
    end

    def wipe_database_tables!
      LockedCV::SensitiveData.dataset.delete
      LockedCV::File.dataset.delete
      LockedCV::User.dataset.delete
    end

    def load_seed_data!
      seeded_users.each { |user| LockedCV::User.create(user) }
      seeded_files.each { |file| LockedCV::File.create(file) }
      seeded_sensitive_data.each { |sensitive_data| LockedCV::SensitiveData.create(sensitive_data) }
    end

    def reset_database_with_seeds!
      ensure_database_schema!
      wipe_database_tables!
      load_seed_data!
    end
  end
end
