# frozen_string_literal: true

require_relative '../spec_helper'

describe 'BuildPdfplumberMaskedPdf' do
  include LockedCV::SpecHelpers

  def setup
    @output_path = 'tmp/test_alan_wrapper_masked.pdf'
    FileUtils.rm_f(@output_path)
  end

  def teardown
    FileUtils.rm_f(@output_path)
  end

  it 'HAPPY: creates a masked output PDF from the fixture' do
    python_bin = available_pdf_processor_python
    skip 'pdfplumber/reportlab Python dependencies are not available' unless python_bin

    with_python_bin(python_bin) do
      result = LockedCV::BuildPdfplumberMaskedPdf.call(
        input_path: 'spec/fixtures/files/fake_resume_alan.pdf',
        output_path: @output_path,
        sensitive_items: sensitive_items
      )

      _(result).must_equal @output_path
      _(File.file?(@output_path)).must_equal true
    end
  end

  it 'HAPPY: output PDF text layer does not contain original sensitive values' do
    python_bin = available_pdf_processor_python
    skip 'pdfplumber/reportlab Python dependencies are not available' unless python_bin

    with_python_bin(python_bin) do
      LockedCV::BuildPdfplumberMaskedPdf.call(
        input_path: 'spec/fixtures/files/fake_resume_alan.pdf',
        output_path: @output_path,
        sensitive_items: sensitive_items
      )
    end

    output_text = LockedCV::ExtractPdf.text(@output_path)
    _(output_text).wont_include 'Alan Turing'
    _(output_text).wont_include 'alan@example.com'
    _(output_text).wont_include '0912-000-002'
    _(output_text).wont_include 'B987654321'
  end

  it 'BAD: missing input path raises a service error' do
    error = _(proc do
      LockedCV::BuildPdfplumberMaskedPdf.call(
        input_path: 'spec/fixtures/files/missing.pdf',
        output_path: @output_path,
        sensitive_items: sensitive_items
      )
    end).must_raise LockedCV::BuildPdfplumberMaskedPdf::Error

    _(error.message).must_include 'Input PDF does not exist'
  end

  it 'BAD: failed Python execution raises a clear service error' do
    with_python_bin('false') do
      error = _(proc do
        LockedCV::BuildPdfplumberMaskedPdf.call(
          input_path: 'spec/fixtures/files/fake_resume_alan.pdf',
          output_path: @output_path,
          sensitive_items: sensitive_items
        )
      end).must_raise LockedCV::BuildPdfplumberMaskedPdf::Error

      _(error.message).must_include 'Python processor failed'
    end
  end

  def sensitive_items
    [
      { field_name: 'full_name', value: 'Alan Turing', kind: 'full_name', label: 'NAME' },
      { 'field_name' => 'email', 'value' => 'alan@example.com', 'kind' => 'email', 'label' => 'EMAIL' },
      { field_name: 'phone_number', value: '0912-000-002', kind: 'phone', label: 'TEL' },
      { field_name: 'identification_number', value: 'B987654321', kind: 'id_number', label: 'ID' }
    ]
  end

  def available_pdf_processor_python
    [
      ENV.fetch('PYTHON_BIN', nil),
      '/tmp/lockedcv-pdfspike-venv/bin/python',
      'python3'
    ].compact.find { |candidate| python_has_processor_dependencies?(candidate) }
  end

  def python_has_processor_dependencies?(python_bin)
    _stdout, _stderr, status = Open3.capture3(python_bin, '-c', 'import pdfplumber, reportlab')
    status.success?
  rescue SystemCallError
    false
  end

  def with_python_bin(python_bin)
    original = ENV.fetch('PYTHON_BIN', nil)
    ENV['PYTHON_BIN'] = python_bin
    yield
  ensure
    original ? ENV['PYTHON_BIN'] = original : ENV.delete('PYTHON_BIN')
  end
end
