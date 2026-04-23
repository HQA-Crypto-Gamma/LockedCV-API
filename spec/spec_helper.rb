# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'json'
require 'date'
require 'logger'
require 'minitest/autorun'
require 'minitest/rg'
require 'rack/test'
require 'stringio'
require 'yaml'

require_relative 'test_load_all'

require_relative '../require_app'
require_app

DATA = {} # rubocop:disable Style/MutableConstant
DATA[:users] = YAML.safe_load_file('db/seeds/user_seeds.yml')
DATA[:attachments] = YAML.safe_load_file('db/seeds/attachment_seeds.yml')
DATA[:sensitive_data] = YAML.safe_load_file(
  'db/seeds/sensitive_data_seeds.yml',
  permitted_classes: [Date]
)

module LockedCV
  # Shared helpers for spec setup/teardown and database seed loading
  module SpecHelpers
    REQUIRED_TABLES = %i[users attachments sensitive_data].freeze

    def db
      LockedCV::Api.DB
    end

    def ensure_database_schema!
      missing_tables = REQUIRED_TABLES.reject { |table| db.table_exists?(table) }
      return if missing_tables.empty?

      raise "Missing tables: #{missing_tables.join(', ')}. Run `bundle exec rake db:migrate` first."
    end

    def wipe_database_tables!
      LockedCV::SensitiveData.dataset.delete
      LockedCV::Attachment.dataset.delete
      LockedCV::User.dataset.delete
    end

    def reset_database!
      ensure_database_schema!
      wipe_database_tables!
    end

    def req_header
      { 'CONTENT_TYPE' => 'application/json' }
    end

    def json_body
      JSON.parse(last_response.body)
    end

    def capture_app_logs
      original_logger = LockedCV::Api.logger
      io = StringIO.new
      test_logger = Logger.new(io)
      test_logger.level = Logger::DEBUG

      LockedCV::Api.send(:remove_const, :LOGGER)
      LockedCV::Api.const_set(:LOGGER, test_logger)

      yield io
    ensure
      LockedCV::Api.send(:remove_const, :LOGGER)
      LockedCV::Api.const_set(:LOGGER, original_logger)
    end
  end
end
