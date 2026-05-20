# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'json'
require 'date'
require 'fileutils'
require 'logger'
require 'minitest/autorun'
require 'minitest/rg'
require 'rack/test'
require 'stringio'
require 'webmock/minitest'
require 'yaml'

require_relative 'test_load_all'

require_relative '../require_app'
require_app

DATA = {} # rubocop:disable Style/MutableConstant
DATA[:accounts] = YAML.safe_load_file('db/seeds/account_seeds.yml')
DATA[:attachments] = YAML.safe_load_file('db/seeds/attachment_seeds.yml')
DATA[:sensitive_data] = YAML.safe_load_file(
  'db/seeds/sensitive_data_seeds.yml',
  permitted_classes: [Date]
)

module LockedCV
  # Shared helpers for spec setup/teardown and database seed loading
  # rubocop:disable Metrics/ModuleLength
  module SpecHelpers
    REQUIRED_TABLES = %i[
      accounts attachments sensitive_data masked_attachments masked_items roles accounts_roles
    ].freeze

    def db
      LockedCV::Api.DB
    end

    def ensure_database_schema!
      missing_tables = REQUIRED_TABLES.reject { |table| db.table_exists?(table) }
      return if missing_tables.empty?

      raise "Missing tables: #{missing_tables.join(', ')}. Run `bundle exec rake db:migrate` first."
    end

    def wipe_database_tables!
      LockedCV::MaskedItem.dataset.delete
      LockedCV::MaskedAttachment.dataset.delete
      LockedCV::SensitiveData.dataset.delete
      LockedCV::Attachment.dataset.delete
      LockedCV::Api.DB[:accounts_roles].delete
      LockedCV::Role.dataset.delete
      LockedCV::Account.dataset.delete
    end

    def reset_database!
      ensure_database_schema!
      wipe_database_tables!
    end

    def reset_storage!
      FileUtils.rm_rf('storage/uploads')
    end

    def storage_path_for(route)
      File.expand_path(File.join('storage/uploads', route), Dir.pwd)
    end

    def req_header
      { 'CONTENT_TYPE' => 'application/json' }
    end

    def auth_header(account)
      token = LockedCV::AuthToken.new(
        'account_id' => account.id,
        'username' => account.username,
        'email' => account.email
      ).to_s

      { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
    end

    def auth_req_header(account)
      req_header.merge(auth_header(account))
    end

    def json_body
      JSON.parse(last_response.body)
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def write_text_pdf(path, text)
      escaped_text = text.gsub('\\', '\\\\\\').gsub('(', '\\(').gsub(')', '\\)')
      objects = [
        '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj',
        '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj',
        '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] ' \
        '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >> endobj',
        '4 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj'
      ]
      stream = "BT /F1 12 Tf 72 720 Td (#{escaped_text}) Tj ET\n"
      objects << "5 0 obj << /Length #{stream.bytesize} >> stream\n" \
                 "#{stream}endstream endobj"

      body = +"%PDF-1.4\n"
      offsets = objects.map do |object|
        offset = body.bytesize
        body << "#{object}\n"
        offset
      end
      xref_offset = body.bytesize
      body << "xref\n0 #{objects.length + 1}\n"
      body << "0000000000 65535 f \n"
      offsets.each { |offset| body << format('%010d 00000 n ', offset) << "\n" }
      body << "trailer << /Root 1 0 R /Size #{objects.length + 1} >>\n"
      body << "startxref\n#{xref_offset}\n%%EOF\n"

      File.binwrite(path, body)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def write_hex_text_pdf(path, text)
      hex_text = text.bytes.map { |byte| format('%02X', byte) }.join
      objects = [
        '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj',
        '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj',
        '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] ' \
        '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >> endobj',
        '4 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj'
      ]
      stream = "BT /F1 12 Tf 72 720 Td <#{hex_text}> Tj ET\n"
      objects << "5 0 obj << /Length #{stream.bytesize} >> stream\n" \
                 "#{stream}endstream endobj"

      body = +"%PDF-1.4\n"
      offsets = objects.map do |object|
        offset = body.bytesize
        body << "#{object}\n"
        offset
      end
      xref_offset = body.bytesize
      body << "xref\n0 #{objects.length + 1}\n"
      body << "0000000000 65535 f \n"
      offsets.each { |offset| body << format('%010d 00000 n ', offset) << "\n" }
      body << "trailer << /Root 1 0 R /Size #{objects.length + 1} >>\n"
      body << "startxref\n#{xref_offset}\n%%EOF\n"

      File.binwrite(path, body)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

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
  # rubocop:enable Metrics/ModuleLength
end
