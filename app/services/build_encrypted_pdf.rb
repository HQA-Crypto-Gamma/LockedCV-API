# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'securerandom'

module LockedCV
  # Builds a temporary password-protected PDF using qpdf.
  class BuildEncryptedPdf
    class Error < StandardError; end

    ENCRYPTED_DIR = File.join('tmp', 'encrypted_pdfs')

    def self.call(input_path:, password:)
      new(input_path:, password:).call
    end

    def initialize(input_path:, password:)
      @input_path = input_path.to_s
      @password = password.to_s
    end

    def call
      validate!
      FileUtils.mkdir_p(ENCRYPTED_DIR)
      output_path = encrypted_path
      _stdout, stderr, status = Open3.capture3(*qpdf_command(output_path))

      raise Error, sanitize_error(stderr) unless status.success?
      raise Error, 'Encrypted PDF was not created' unless File.file?(output_path)

      output_path
    rescue SystemCallError => e
      raise Error, e.message
    end

    private

    attr_reader :input_path, :password

    def validate!
      raise Error, 'Password is required' if password.strip.empty?
      raise Error, "Input PDF does not exist: #{input_path}" unless File.file?(input_path)
    end

    def qpdf_command(output_path)
      [
        'qpdf',
        '--encrypt',
        password,
        SecureRandom.hex(24),
        '256',
        '--',
        input_path,
        output_path
      ]
    end

    def encrypted_path
      File.join(ENCRYPTED_DIR, "encrypted_#{SecureRandom.uuid}.pdf")
    end

    def sanitize_error(stderr)
      message = stderr.to_s.gsub(/\s+/, ' ').strip[0, 500]
      message.empty? ? 'Could not encrypt PDF' : message
    end
  end
end
