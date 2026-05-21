# frozen_string_literal: true

require 'pdf/reader'

module LockedCV
  # Extracts text from text-based PDF files.
  class ExtractPdf
    class FileNotFoundError < StandardError; end

    def self.text(path)
      resolved_path = resolve_path(path)
      raise FileNotFoundError unless File.file?(resolved_path)

      PDF::Reader.new(resolved_path).pages.map(&:text).join("\n")
    end

    def self.resolve_path(path)
      File.expand_path(path, Dir.pwd)
    end
    private_class_method :resolve_path
  end
end
