# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'securerandom'

module LockedCV
  # Adapter service that invokes the Python pdfplumber masked-PDF processor.
  class BuildPdfplumberMaskedPdf
    class Error < StandardError; end

    TMP_DIR = 'tmp'

    def self.call(input_path:, output_path:, sensitive_items:)
      new(input_path:, output_path:, sensitive_items:).call
    end

    def initialize(input_path:, output_path:, sensitive_items:)
      @input_path = input_path.to_s
      @output_path = output_path.to_s
      @sensitive_items = sensitive_items
      @payload_path = nil
    end

    def call
      validate!
      FileUtils.mkdir_p(File.dirname(output_path))
      write_payload
      run_processor
      validate_output!

      output_path
    ensure
      cleanup_payload
    end

    private

    attr_reader :input_path, :output_path, :sensitive_items, :payload_path

    def validate!
      raise Error, "Input PDF does not exist: #{input_path}" unless File.file?(input_path)
      raise Error, 'Output path is required' if output_path.strip.empty?
      raise Error, 'Sensitive items must be an array' unless sensitive_items.is_a?(Array)
      raise Error, "Python processor does not exist: #{processor_path}" unless File.file?(processor_path)
    end

    def write_payload
      FileUtils.mkdir_p(TMP_DIR)
      @payload_path = File.join(TMP_DIR, "pdf_mask_payload_#{SecureRandom.uuid}.json")
      File.write(payload_path, JSON.pretty_generate(payload_hash))
    end

    def payload_hash
      {
        sensitive_items: sensitive_items.map { |item| normalize_item(item) }
      }
    end

    def normalize_item(item)
      raise Error, 'Sensitive items must be hashes' unless item.is_a?(Hash)

      {
        field_name: item_value(item, :field_name),
        value: item_value(item, :value),
        kind: item_value(item, :kind),
        label: item_value(item, :label)
      }.compact
    end

    def item_value(item, key)
      item[key] || item[key.to_s]
    end

    def run_processor
      stdout, stderr, status = Open3.capture3(*processor_command)
      return if status.success?

      raise Error, processor_error_message(status:, stdout:, stderr:)
    rescue SystemCallError => e
      raise Error, "Could not run Python processor: #{e.message}"
    end

    def processor_command
      [
        python_bin, processor_path,
        '--input', input_path,
        '--output', output_path,
        '--payload', payload_path
      ]
    end

    def processor_error_message(status:, stdout:, stderr:)
      details = [stderr, stdout].map { |text| sanitize_process_output(text) }.reject(&:empty?).join(' ')
      message = "Python processor failed with status #{status.exitstatus}"
      details.empty? ? message : "#{message}: #{details}"
    end

    def sanitize_process_output(text)
      text.to_s.gsub(/\s+/, ' ').strip[0, 500]
    end

    def validate_output!
      raise Error, "Python processor did not create output PDF: #{output_path}" unless File.file?(output_path)
    end

    def cleanup_payload
      return unless payload_path && File.exist?(payload_path)

      FileUtils.rm_f(payload_path)
    end

    def processor_path
      @processor_path ||= File.expand_path('../lib/pdf_processors/pdfplumber_masked_pdf.py', __dir__)
    end

    def python_bin
      ENV.fetch('PYTHON_BIN', 'python3')
    end
  end
end
