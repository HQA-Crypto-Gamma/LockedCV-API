# Masked PDF Frontend Integration Plan

This file summarizes how the frontend can call the masked PDF APIs.

## Flow Summary

```text
1. User toggles mask labels
   -> POST preview endpoint
   -> backend returns PDF blob for preview

2. User confirms the mask result
   -> POST create endpoint
   -> backend saves official masked PDF and returns masked_attachment_id

3. User downloads PDF
   -> GET normal download endpoint
   -> frontend downloads the saved masked PDF

4. User downloads encrypted PDF
   -> frontend asks user to enter a password
   -> POST encrypted_download endpoint with password
   -> backend returns password-protected PDF blob
   -> frontend downloads the encrypted PDF
```

## Available Mask Labels

Recommended frontend values:

| UI Label | Value to Send |
|---|---|
| Name | `name` |
| Email | `email` |
| Phone | `tel` |
| ID Number | `id` |
| Birthday | `birthday` |
| Address | `address` |

Supported values:

```text
name
full_name
first_name
last_name
email
tel
phone
phone_number
birthday
address
id
id_number
identification_number
identification_numbers
```

Notes:

- `name` covers `first_name`, `last_name`, and `full_name`.
- `tel` covers `phone` and `phone_number`.
- `id` covers `identification_number` and `identification_numbers`.
- Unknown labels return `400 Invalid selected labels`.
- If `selected_labels` is omitted, backend masks all available sensitive fields.
- If `selected_labels` is `[]`, backend masks nothing.

## 1. Preview Masked PDF

Call this whenever selected labels change.

```http
POST /api/v1/attachments/:attachment_id/masked_attachments/preview
```

Request:

```json
{
  "selected_labels": ["name", "email", "tel"]
}
```

Response:

```http
200 OK
Content-Type: application/pdf
Content-Disposition: inline; filename="masked_preview.pdf"
```

Important:

- Response is a PDF blob, not JSON.
- Preview does not create `masked_attachments`.
- Preview does not create `masked_items`.
- Frontend should debounce this request by about `300–500 ms`.

Example:

```js
async function previewMaskedPdf(attachmentId, selectedLabels, token) {
  const response = await fetch(
    `/api/v1/attachments/${attachmentId}/masked_attachments/preview`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${token}`
      },
      body: JSON.stringify({ selected_labels: selectedLabels })
    }
  );

  if (!response.ok) throw new Error("Failed to preview masked PDF");

  const pdfBlob = await response.blob();
  return URL.createObjectURL(pdfBlob);
}
```

When replacing previews, revoke the old blob URL:

```js
if (currentPreviewUrl) URL.revokeObjectURL(currentPreviewUrl);

currentPreviewUrl = await previewMaskedPdf(attachmentId, selectedLabels, token);
pdfViewer.src = currentPreviewUrl;
```

## 2. Create Official Masked PDF

Call this when the user confirms the selected mask result.

```http
POST /api/v1/attachments/:attachment_id/masked_attachments
```

Request:

```json
{
  "selected_labels": ["name", "email", "tel"]
}
```

Response:

```http
201 Created
Content-Type: application/json
Location: api/v1/attachments/:attachment_id/masked_attachments/:masked_attachment_id
```

Example response shape:

```json
{
  "message": "Masked attachment saved",
  "data": {
    "type": "masked_attachment",
    "data": {
      "attributes": {
        "id": "123",
        "attachment_name": "masked_resume.pdf",
        "route": "accounts/.../masked/....pdf"
      }
    }
  }
}
```

Frontend should save the returned `masked_attachment_id` for download.

## 3. Download Saved Masked PDF

Call this after an official masked attachment has been created.

```http
GET /api/v1/attachments/:attachment_id/masked_attachments/:masked_attachment_id/download
```

Response:

```http
200 OK
Content-Type: application/pdf
Content-Disposition: attachment; filename="masked_filename.pdf"
```

Example:

```js
async function downloadMaskedPdf(attachmentId, maskedAttachmentId, token) {
  const response = await fetch(
    `/api/v1/attachments/${attachmentId}/masked_attachments/${maskedAttachmentId}/download`,
    {
      method: "GET",
      headers: {
        "Authorization": `Bearer ${token}`
      }
    }
  );

  if (!response.ok) throw new Error("Failed to download masked PDF");

  const pdfBlob = await response.blob();
  const downloadUrl = URL.createObjectURL(pdfBlob);

  const link = document.createElement("a");
  link.href = downloadUrl;
  link.download = "masked_attachment.pdf";
  document.body.appendChild(link);
  link.click();
  link.remove();

  URL.revokeObjectURL(downloadUrl);
}
```

## 4. Download Encrypted Masked PDF

Call this when the user wants to download a password-protected PDF.

Frontend behavior:

```text
User clicks encrypted download
-> frontend opens password modal
-> user enters password
-> frontend POSTs password to backend
-> backend returns encrypted PDF blob
-> frontend triggers local download
```

Endpoint:

```http
POST /api/v1/attachments/:attachment_id/masked_attachments/:masked_attachment_id/encrypted_download
```

Request:

```json
{
  "password": "user-entered-password"
}
```

Response:

```http
200 OK
Content-Type: application/pdf
Content-Disposition: attachment; filename="encrypted_masked_filename.pdf"
```

Important:

- Response is a password-protected PDF blob.
- The password is provided by the user through the frontend.
- Backend does not save a new `masked_attachments` record for encrypted downloads.
- Blank password returns `400`.

Example:

```js
async function downloadEncryptedMaskedPdf(
  attachmentId,
  maskedAttachmentId,
  password,
  token
) {
  const response = await fetch(
    `/api/v1/attachments/${attachmentId}/masked_attachments/${maskedAttachmentId}/encrypted_download`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${token}`
      },
      body: JSON.stringify({ password })
    }
  );

  if (!response.ok) throw new Error("Failed to download encrypted PDF");

  const pdfBlob = await response.blob();
  const downloadUrl = URL.createObjectURL(pdfBlob);

  const link = document.createElement("a");
  link.href = downloadUrl;
  link.download = "encrypted_masked_attachment.pdf";
  document.body.appendChild(link);
  link.click();
  link.remove();

  URL.revokeObjectURL(downloadUrl);
}
```

## Suggested Frontend Flow

```text
Initial page load
-> prepare selectedLabels state

User toggles label
-> update selectedLabels
-> debounce 300–500 ms
-> POST preview endpoint
-> update PDF viewer with returned blob URL

User confirms mask result
-> POST create endpoint with selectedLabels
-> save returned masked_attachment_id

User clicks normal download
-> GET download endpoint
-> download PDF blob

User clicks encrypted download
-> ask user for password
-> POST encrypted_download with password
-> download encrypted PDF blob
```

## Error Handling

Invalid selected labels:

```json
{
  "message": "Invalid selected labels"
}
```

Missing or unauthorized attachment:

```json
{
  "message": "Attachment not found"
}
```

Missing or unauthorized masked attachment:

```json
{
  "message": "Masked attachment not found"
}
```

Encrypted download failure, including blank password:

```json
{
  "message": "Could not encrypt masked attachment"
}
```

## Important Notes

- Preview response is PDF.
- Create response is JSON.
- Normal download response is PDF.
- Encrypted download response is PDF.
- Preview does not save database records.
- Create saves the official masked PDF.
- Encrypted download does not create a new masked attachment record.
- Gray mask boxes should not contain label text such as `NAME`, `EMAIL`, `TEL`, or `ID`.
- Use blob handling for all PDF responses.
- Debounce preview requests.
