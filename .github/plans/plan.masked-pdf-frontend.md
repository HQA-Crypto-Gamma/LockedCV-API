# Masked PDF Frontend Integration Plan

This document explains how the frontend can integrate with the masked PDF preview, creation, and download workflow.

## Overview

The masked PDF workflow is now separated into three steps:

```text
Preview  -> generate a temporary masked PDF for display
Create   -> save the confirmed masked PDF as an official record
Download -> download the saved masked PDF
```

The main frontend use case is:

1. User opens the masking page for an attachment.
2. User selects or unselects sensitive labels such as `email`, `tel`, `id`, etc.
3. Frontend sends the current selected labels to the preview endpoint.
4. Backend returns a PDF binary response.
5. Frontend updates the PDF viewer using the returned PDF blob.
6. When the user confirms, frontend sends the same selected labels to the create endpoint.
7. Backend saves the official masked PDF and returns a masked attachment record.
8. Frontend can call the download endpoint to download the saved masked PDF.

## Available Mask Labels

The backend supports the following selected label values:

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

Recommended frontend labels:

| UI Label  | Value to Send |
| --------- | ------------- |
| Name      | `name`        |
| Email     | `email`       |
| Phone     | `tel`         |
| ID Number | `id`          |
| Birthday  | `birthday`    |
| Address   | `address`     |

Notes:

* `name` will cover name-related fields such as `first_name`, `last_name`, and `full_name`.
* `tel` will cover phone-related fields such as `phone` and `phone_number`.
* `id` will cover identification-related fields such as `identification_number` and `identification_numbers`.
* Unknown labels will return `400 Invalid selected labels`.
* If `selected_labels` is omitted, the backend treats it as masking all available sensitive fields.
* If `selected_labels` is an empty array, the backend treats it as masking nothing.

## 1. Preview Masked PDF

Use this endpoint whenever the user changes the selected mask labels.

```http
POST /api/v1/attachments/:attachment_id/masked_attachments/preview
```

### Request Body

```json
{
  "selected_labels": ["name", "email", "tel"]
}
```

### Response

```http
HTTP/1.1 200 OK
Content-Type: application/pdf
Content-Disposition: inline; filename="masked_preview.pdf"
```

The response body is a PDF binary.

This endpoint is for preview only.

It does not:

* create a `masked_attachments` database record
* create `masked_items`
* permanently save the preview PDF

### Suggested Frontend Usage

```js
async function fetchMaskedPdfPreview(attachmentId, selectedLabels, token) {
  const response = await fetch(
    `/api/v1/attachments/${attachmentId}/masked_attachments/preview`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${token}`
      },
      body: JSON.stringify({
        selected_labels: selectedLabels
      })
    }
  );

  if (!response.ok) {
    throw new Error("Failed to preview masked PDF");
  }

  const pdfBlob = await response.blob();
  return URL.createObjectURL(pdfBlob);
}
```

Example usage with an iframe:

```js
const previewUrl = await fetchMaskedPdfPreview(
  attachmentId,
  ["name", "email", "tel"],
  token
);

document.querySelector("#pdf-preview").src = previewUrl;
```

If the frontend creates multiple blob URLs, remember to revoke old URLs when replacing the preview:

```js
if (currentPreviewUrl) {
  URL.revokeObjectURL(currentPreviewUrl);
}

currentPreviewUrl = await fetchMaskedPdfPreview(
  attachmentId,
  selectedLabels,
  token
);

pdfViewer.src = currentPreviewUrl;
```

## Frontend Debounce Recommendation

PDF generation is heavier than normal JSON API calls.

When the user toggles labels, the frontend should debounce preview requests.

Recommended debounce time:

```text
300–500 ms
```

Suggested behavior:

```text
User toggles label
-> update selectedLabels state
-> wait 300–500 ms
-> POST selectedLabels to preview endpoint
-> receive PDF blob
-> update PDF preview
```

This avoids sending too many preview requests when the user clicks labels quickly.

## 2. Create Official Masked PDF

Use this endpoint when the user confirms the selected masking result.

```http
POST /api/v1/attachments/:attachment_id/masked_attachments
```

### Request Body

```json
{
  "selected_labels": ["name", "email", "tel"]
}
```

### Response

```http
HTTP/1.1 201 Created
Content-Type: application/json
Location: api/v1/attachments/:attachment_id/masked_attachments/:masked_attachment_id
```

Example response body:

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

This endpoint does:

* create the official masked PDF
* save the masked PDF file
* create a `masked_attachments` database record
* create related `masked_items`
* return JSON for the saved masked attachment

This endpoint should be called only after the user confirms the masking result.

## 3. Download Saved Masked PDF

Use this endpoint after an official masked attachment has been created.

```http
GET /api/v1/attachments/:attachment_id/masked_attachments/:masked_attachment_id/download
```

### Response

```http
HTTP/1.1 200 OK
Content-Type: application/pdf
Content-Disposition: attachment; filename="masked_filename.pdf"
```

The response body is a PDF binary.

### Suggested Frontend Usage

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

  if (!response.ok) {
    throw new Error("Failed to download masked PDF");
  }

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

## Suggested Frontend Flow

```text
Initial page load
-> prepare selectedLabels state

User toggles a label
-> update selectedLabels
-> debounce
-> POST preview endpoint
-> receive PDF blob
-> update PDF viewer

User clicks confirm/download
-> POST create endpoint with selectedLabels
-> receive masked_attachment_id
-> GET download endpoint
-> download saved PDF
```

## Error Handling

### Invalid selected labels

If the frontend sends an unsupported label:

```json
{
  "selected_labels": ["unknown"]
}
```

Backend response:

```http
HTTP/1.1 400 Bad Request
```

```json
{
  "message": "Invalid selected labels"
}
```

### Attachment not found or unauthorized

Backend may return:

```http
HTTP/1.1 404 Not Found
```

```json
{
  "message": "Attachment not found"
}
```

or:

```json
{
  "message": "Masked attachment not found"
}
```

## Important Notes

* Preview response is a PDF file, not JSON.
* Create response is JSON.
* Download response is a PDF file.
* Preview does not save records to the database.
* Create saves the official masked PDF.
* Download only works for an existing saved masked PDF.
* The gray mask boxes should not contain text labels such as `NAME`, `EMAIL`, `TEL`, or `ID`.
* The frontend should use blob handling for preview and download responses.
* Debouncing preview requests is strongly recommended.
