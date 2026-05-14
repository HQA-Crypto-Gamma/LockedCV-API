# frozen_string_literal: true

require 'pdf/reader'

module LockedCV
  # Extracts text and text-run positions from text-based PDF files.
  class ExtractPdf
    class FileNotFoundError < StandardError; end

    def self.text(path)
      resolved_path = resolve_path(path)
      raise FileNotFoundError unless File.file?(resolved_path)

      PDF::Reader.new(resolved_path).pages.map(&:text).join("\n")
    end

    def self.positioned_text(path)
      resolved_path = resolve_path(path)
      raise FileNotFoundError unless File.file?(resolved_path)

      PDF::Reader.new(resolved_path).pages.each_with_index.flat_map do |page, index|
        positioned_page_text(page:, page_number: index + 1)
      end
    end

    def self.resolve_path(path)
      File.expand_path(path, Dir.pwd)
    end
    private_class_method :resolve_path

    def self.positioned_page_text(page:, page_number:)
      receiver = PDF::Reader::PageTextReceiver.new
      page.walk(receiver)
      receiver.runs.map { |run| text_fragment(run:, page_number:) }
    end
    private_class_method :positioned_page_text

    def self.text_fragment(run:, page_number:)
      {
        text: run.text,
        page_number:,
        x: run.x,
        y: run.y,
        width: run.width,
        height: run.font_size
      }
    end
    private_class_method :text_fragment
  end
end
