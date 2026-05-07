# frozen_string_literal: true

require 'fileutils'
require 'securerandom'

module LockedCV
  # Stores uploaded PDF attachments under controlled local storage.
  class StoreAttachmentFile
    class MissingFileError < StandardError; end
    class InvalidFileError < StandardError; end

    PDF_MAGIC = '%PDF-'

    def self.call(uploaded_file:, account_id:)
      raise MissingFileError unless uploaded_file

      tempfile = uploaded_value(uploaded_file, :tempfile)
      original_filename = uploaded_value(uploaded_file, :filename)
      validate_pdf_upload!(tempfile:, original_filename:)

      route = storage_route(account_id:, original_filename:)
      full_path = File.join(ResolveAttachmentPath::STORAGE_ROOT, route)
      FileUtils.mkdir_p(File.dirname(full_path))
      tempfile.rewind
      File.open(full_path, 'wb') { |file| IO.copy_stream(tempfile, file) }

      route
    end

    def self.delete(route:)
      path = ResolveAttachmentPath.call(route:)
      FileUtils.rm_f(path)
      remove_empty_parent(File.dirname(path))
    rescue ResolveAttachmentPath::MissingFileError, ResolveAttachmentPath::UnsafePathError
      nil
    end

    def self.remove_empty_parent(path)
      return if path == ResolveAttachmentPath::STORAGE_ROOT
      return unless Dir.exist?(path) && Dir.empty?(path)

      Dir.rmdir(path)
    end
    private_class_method :remove_empty_parent

    def self.uploaded_value(uploaded_file, key)
      return uploaded_file[key] if uploaded_file.respond_to?(:key?) && uploaded_file.key?(key)
      return uploaded_file[key.to_s] if uploaded_file.respond_to?(:key?) && uploaded_file.key?(key.to_s)

      nil
    end
    private_class_method :uploaded_value

    def self.validate_pdf_upload!(tempfile:, original_filename:)
      raise MissingFileError unless tempfile
      raise InvalidFileError unless File.extname(original_filename.to_s).casecmp?('.pdf')

      tempfile.rewind
      raise InvalidFileError unless tempfile.read(PDF_MAGIC.length) == PDF_MAGIC

      tempfile.rewind
    end
    private_class_method :validate_pdf_upload!

    def self.storage_route(account_id:, original_filename:)
      File.join(
        'accounts',
        safe_segment(account_id),
        generated_filename(original_filename)
      )
    end
    private_class_method :storage_route

    def self.generated_filename(original_filename)
      basename = File.basename(original_filename.to_s, '.*')
      safe_basename = safe_segment(basename).downcase
      safe_basename = 'attachment' if safe_basename.empty?

      "#{safe_basename}_#{SecureRandom.hex(16)}.pdf"
    end
    private_class_method :generated_filename

    def self.safe_segment(value)
      value.to_s.gsub(/[^A-Za-z0-9_-]+/, '_').gsub(/\A_+|_+\z/, '')
    end
    private_class_method :safe_segment
  end
end
