# frozen_string_literal: true

require 'pdf/reader'

module LockedCV
  # Extracts readable text from text-based PDF files.
  class ExtractPdfText
    class FileNotFoundError < StandardError; end

    def self.call(file_path:)
      path = resolve_path(file_path)
      raise FileNotFoundError unless File.file?(path)

      PDF::Reader.new(path).pages.map(&:text).join("\n")
    end

    def self.resolve_path(file_path)
      File.expand_path(file_path, Dir.pwd)
    end
    private_class_method :resolve_path
  end
end
