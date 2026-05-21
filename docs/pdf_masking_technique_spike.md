# PDF Masking Technique Spike

## Production Python Processor Draft

The first production-oriented draft of the pdfplumber masking processor lives
under:

```text
app/lib/pdf_processors/pdfplumber_masked_pdf.py
```

It lives under `app/lib/pdf_processors/` because it is application support code
intended for a later Ruby service integration, but it is not connected to the
Roda API flow yet. The processor is independently runnable and does not
hard-code fixture paths.

Manual smoke-test command:

```bash
python3 app/lib/pdf_processors/pdfplumber_masked_pdf.py \
  --input spec/fixtures/files/fake_resume_alan.pdf \
  --output tmp/pdfplumber_test/alan_processor_masked.pdf \
  --payload tmp/pdfplumber_test/alan_payload.json
```

Payload shape:

```json
{
  "sensitive_items": [
    {"field_name": "full_name", "value": "Alan Turing", "kind": "full_name", "label": "NAME"},
    {"field_name": "email", "value": "alan@example.com", "kind": "email", "label": "EMAIL"},
    {"field_name": "phone_number", "value": "0912-000-002", "kind": "phone", "label": "TEL"},
    {"field_name": "identification_number", "value": "B987654321", "kind": "id_number", "label": "ID"}
  ]
}
```

Required Python dependencies:

```bash
pip install pdfplumber reportlab
```

Smoke-test result:

- Output generated successfully:
  `tmp/pdfplumber_test/alan_processor_masked.pdf`.
- Pages processed: 1.
- Words extracted: 236.
- Sensitive phrases matched: 10.
- Original sensitive tokens skipped: 13.
- Labels drawn: 10.
- Vector lines restored: 6.
- Vector rects restored: 0.
- Text-layer check: `Alan Turing`, `alan@example.com`, `0912-000-002`,
  and `B987654321` were not found.

Remaining limitations:

- The Ruby application does not call this processor yet.
- It is still an approximate PDF rebuild, not full content-stream redaction.
- It does not restore images, icons, complex curves, or embedded font fidelity.
- Matching is based on extracted pdfplumber words, so unusual PDF encodings or
  text order may need additional tuning.
- Generated PDFs from smoke tests should stay under `tmp/` and should not be
  committed.

## Ruby Wrapper Service

The Ruby wrapper service lives under:

```text
app/services/build_pdfplumber_masked_pdf.rb
```

The wrapper exists so the Ruby/Roda application can call the production Python
processor without duplicating PDF parsing or layout rebuilding in Ruby. It is
an adapter only: it validates paths, writes a temporary JSON payload, invokes
the Python processor, checks the exit status and output file, and deletes the
temporary payload file.

Ruby calls Python with `Open3.capture3`:

```ruby
stdout, stderr, status = Open3.capture3(
  python_bin,
  processor_path,
  '--input', input_path,
  '--output', output_path,
  '--payload', payload_path
)
```

The Python executable defaults to `python3`. Override it with `PYTHON_BIN` when
using a virtual environment:

```bash
PYTHON_BIN=/tmp/lockedcv-pdfspike-venv/bin/python ruby -r ./spec/spec_helper -e "..."
```

Manual wrapper smoke test:

```ruby
LockedCV::BuildPdfplumberMaskedPdf.new(
  input_path: 'spec/fixtures/files/fake_resume_alan.pdf',
  output_path: 'tmp/alan_wrapper_masked.pdf',
  sensitive_items: [
    { field_name: 'full_name', value: 'Alan Turing', kind: 'full_name', label: 'NAME' },
    { field_name: 'email', value: 'alan@example.com', kind: 'email', label: 'EMAIL' },
    { field_name: 'phone_number', value: '0912-000-002', kind: 'phone', label: 'TEL' },
    { field_name: 'identification_number', value: 'B987654321', kind: 'id_number', label: 'ID' }
  ]
).call
```

Dependency notes:

- Ruby uses stdlib `json`, `open3`, `securerandom`, and `fileutils`.
- Python still requires `pdfplumber` and `reportlab`.
- The wrapper is not connected to `ExportMaskedPdf` yet.
