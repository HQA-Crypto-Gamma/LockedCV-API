# frozen_string_literal: true

require 'tempfile'
require_relative '../spec_helper'

describe 'Attachment Storage Services' do
  include LockedCV::SpecHelpers

  before do
    reset_database!
    reset_storage!
  end

  after do
    reset_storage!
  end

  def uploaded_file(path:, filename:, type: 'application/pdf')
    {
      filename:,
      type:,
      tempfile: File.open(path, 'rb')
    }
  end

  it 'HAPPY: stores uploaded PDFs under controlled local storage' do
    pdf = Tempfile.new(['lockedcv-upload', '.pdf'])
    write_text_pdf(pdf.path, 'Stored PDF text')
    upload = uploaded_file(path: pdf.path, filename: 'Resume Ada.pdf')

    route = LockedCV::StoreAttachmentFile.call(uploaded_file: upload, account_id: 'account-123')

    _(route).must_match %r{\Aaccounts/account-123/resume_ada_[0-9a-f]{32}\.pdf\z}
    _(route).wont_match %r{\A/}
    _(File.file?(storage_path_for(route))).must_equal true
  ensure
    upload&.fetch(:tempfile)&.close
    pdf&.close!
  end

  it 'SAD: rejects non-PDF uploads' do
    text_file = Tempfile.new(['lockedcv-upload', '.txt'])
    text_file.write('not a pdf')
    text_file.rewind
    upload = uploaded_file(path: text_file.path, filename: 'resume.txt', type: 'text/plain')

    _(
      proc { LockedCV::StoreAttachmentFile.call(uploaded_file: upload, account_id: 'account-123') }
    ).must_raise LockedCV::StoreAttachmentFile::InvalidFileError
  ensure
    upload&.fetch(:tempfile)&.close
    text_file&.close!
  end

  it 'SAD: rejects missing uploads' do
    _(
      proc { LockedCV::StoreAttachmentFile.call(uploaded_file: nil, account_id: 'account-123') }
    ).must_raise LockedCV::StoreAttachmentFile::MissingFileError
  end

  it 'HAPPY: resolves stored attachment routes to safe full paths' do
    pdf = Tempfile.new(['lockedcv-resolve', '.pdf'])
    write_text_pdf(pdf.path, 'Resolvable PDF text')
    upload = uploaded_file(path: pdf.path, filename: 'resume.pdf')
    route = LockedCV::StoreAttachmentFile.call(uploaded_file: upload, account_id: 'account-123')

    full_path = LockedCV::ResolveAttachmentPath.call(route:)

    _(full_path).must_equal storage_path_for(route)
  ensure
    upload&.fetch(:tempfile)&.close
    pdf&.close!
  end

  it 'HAPPY: deletes stored attachment files by route' do
    pdf = Tempfile.new(['lockedcv-delete', '.pdf'])
    write_text_pdf(pdf.path, 'Deletable PDF text')
    upload = uploaded_file(path: pdf.path, filename: 'resume.pdf')
    route = LockedCV::StoreAttachmentFile.call(uploaded_file: upload, account_id: 'account-123')

    LockedCV::StoreAttachmentFile.delete(route:)

    _(File.file?(storage_path_for(route))).must_equal false
  ensure
    upload&.fetch(:tempfile)&.close
    pdf&.close!
  end

  it 'SECURITY: rejects parent directory traversal routes' do
    _(
      proc { LockedCV::ResolveAttachmentPath.call(route: '../config/secrets.yml') }
    ).must_raise LockedCV::ResolveAttachmentPath::UnsafePathError
  end

  it 'SECURITY: rejects absolute paths outside storage root' do
    _(
      proc { LockedCV::ResolveAttachmentPath.call(route: '/etc/passwd') }
    ).must_raise LockedCV::ResolveAttachmentPath::UnsafePathError
  end

  it 'SECURITY: rejects symlinks that resolve outside storage root' do
    outside_file = Tempfile.new(['lockedcv-outside-storage', '.pdf'])
    outside_file.write('%PDF-1.4 outside storage')
    outside_file.close
    route = 'accounts/account-123/linked.pdf'
    link_path = storage_path_for(route)
    FileUtils.mkdir_p(File.dirname(link_path))

    begin
      File.symlink(outside_file.path, link_path)
    rescue NotImplementedError, Errno::EACCES
      skip 'symlinks are not available in this environment'
    end

    _(
      proc { LockedCV::ResolveAttachmentPath.call(route:) }
    ).must_raise LockedCV::ResolveAttachmentPath::UnsafePathError
  ensure
    FileUtils.rm_f(link_path) if link_path
    outside_file&.unlink
  end

  it 'HAPPY: extracts text from a fixture PDF' do
    text = LockedCV::ExtractPdf.text('spec/fixtures/files/sample_text.pdf')

    _(text).must_include 'LockedCV fixture PDF'
  end
end
