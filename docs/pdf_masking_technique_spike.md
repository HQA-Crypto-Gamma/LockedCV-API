# PDF Masking Technique Spike

## Production Python Processor Draft

The first production-oriented draft of the pdfplumber masking processor lives
under:

```text
app/lib/pdf_processors/pdfplumber_masked_pdf.py
```

It lives under `app/lib/pdf_processors/` because it is application support code
called by the Ruby wrapper service, while remaining independently runnable for
manual smoke tests. It does not hard-code fixture paths.

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

- The processor is called through the Ruby wrapper service, not directly by
  controllers.
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
- `ExportMaskedPdf` now calls the wrapper for masked PDF generation.

## ExportMaskedPdf Integration

`ExportMaskedPdf` now uses the Ruby wrapper service for PDF generation:

```text
ExportMaskedPdf
-> ResolveAttachmentPath
-> ExtractPdf.text
-> MaskSensitiveText.matches_for_masking
-> BuildPdfplumberMaskedPdf
-> app/lib/pdf_processors/pdfplumber_masked_pdf.py
```

Ruby still owns the application workflow:

- attachment lookup
- sensitive data lookup through decrypted model getters
- masked output route generation under `storage/uploads`
- masked attachment record creation
- masked item record creation
- encrypted masked item value persistence through model setters

The Python processor only receives an input PDF path, output PDF path, and JSON
payload. It generates the output PDF and does not read or write the database.

Sensitive matches are converted into payload items before invoking Python. Each
item includes:

```ruby
{
  field_name: 'email',
  value: 'alan@example.com',
  kind: 'email',
  label: 'EMAIL'
}
```

For stored first and last names, Ruby also sends a synthesized `full_name`
payload item when both values are present. This lets the Python processor match
`Alan Turing` as one phrase before shorter first-name or last-name values. The
original individual matches still drive `masked_items` records, preserving the
existing metadata behavior.

Storage route decisions remain in `ExportMaskedPdf`; the wrapper receives the
already resolved absolute input path and the absolute output path under the
existing storage root.

Remaining notes:

- `PYTHON_BIN` can point to a virtual environment Python with `pdfplumber` and
  `reportlab` installed.
- `ExportMaskedPdf` is still an approximate masked-PDF export, not a formal PDF
  redaction engine.
- Older Ruby-only PDF rebuild helpers remain in the codebase for now and can be
  cleaned up separately after the integration settles.

## System-Based Review Artifact

Generate the visual review artifact with:

```bash
ruby tools/generate_system_masked_pdf_review.rb
```

The script uses the real LockedCV Ruby system flow. It creates a review account,
stores `spec/fixtures/files/fake_resume_alan.pdf` through
`StoreAttachmentFile`, creates attachment metadata and `SensitiveData`, calls
`ExportMaskedPdf`, then copies the generated masked PDF from the normal storage
route to:

```text
spec/fixtures/generated/alan_system_masked_pdfplumber.pdf
```

The generated artifact is for local visual review only and should not be
committed. `.gitignore` excludes:

```text
spec/fixtures/generated/*.pdf
```

Latest text-layer check result:

- `Alan Turing`: not found
- `alan@example.com`: not found
- `0912-000-002`: not found
- `B987654321`: not found
- `NAME`: found
- `EMAIL`: found
- `TEL`: found
- `ID`: found

The expected visual review result is a pdfplumber-generated masked PDF with
label boxes where sensitive values were, restored divider lines, approximate
original layout, and no obvious layout reflow caused by labels.
