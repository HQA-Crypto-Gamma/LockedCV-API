# LockedCV API

A Ruby web API for the Crypto γ SEC project that allows users to securely share resumes or other personal documents with automatic personal information hiding. Built with Roda framework and file-based data storage.

## Features

- RESTful API for managing personal data
- File-based JSON storage (no database required)
- Secure ID generation using SHA-256 hashing
- JSON response format

## Prerequisites

- Ruby 4.0.1 (see `.ruby-version`)
- Bundler

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd LockedCV-API
```

2. Install dependencies:
```bash
bundle install
```

## Running the Application

Start the Puma server:
```bash
puma
```

The API will be available at `http://localhost:9292`

## API Endpoints

### Root Endpoint

**GET** `/`

Returns API status message.

```bash
http -v GET localhost:9292/
```

Response:
```json
{
  "message": "LockedCV API up at /api/v1"
}
```

### Personal Data Endpoints

#### Get All Personal Data IDs

**GET** `/api/v1/personal_data`

Returns a list of all personal data entry IDs.

```bash
http -v GET localhost:9292/api/v1/personal_data
```

Response:
```json
{
  "personal_data_ids": [
    "abc123xyz",
    "def456uvw"
  ]
}
```

#### Get Personal Data by ID

**GET** `/api/v1/personal_data/:id`

Retrieve a specific personal data entry.

```bash
http -v GET localhost:9292/api/v1/personal_data/abc123xyz
```

Response:
```json
{
  "type": "personal_data",
  "id": "abc123xyz",
  "first_name": "John",
  "last_name": "Doe",
  "phone": "123-456-7890"
}
```

Error Response (404):
```json
{
  "message": "Personal data not found"
}
```

#### Create Personal Data

**POST** `/api/v1/personal_data`

Create a new personal data entry.

```bash
http -v --json POST localhost:9292/api/v1/personal_data \
  first_name="Jane" \
  last_name="Smith" \
  phone="987-654-3210"
```

Success Response (201):
```json
{
  "message": "Personal data saved",
  "id": "xyz789abc"
}
```

Error Response (400):
```json
{
  "message": "Could not save personal data"
}
```

## Development

### Running Tests

```bash
ruby spec/api_spec.rb
```

### Linting

Run RuboCop to check code style:

```bash
rubocop
```

## Project Structure

```
.
├── app/
│   ├── controllers/
│   │   └── app.rb          # Main Roda controller with API routes
│   └── models/
│       ├── personal_data.rb # PersonalData file-store model
│       ├── user.rb          # User DB model
│       ├── file.rb          # File DB model
│       └── sensitive_data.rb # SensitiveData DB model
├── config.ru                # Rack configuration
├── db/
│   ├── local/              # File storage directory (gitignored)
│   └── seeds/              # Test seed data
├── spec/                    # Test files
└── .github/
    └── copilot-instructions.md  # AI assistant guidelines
```

## Data Storage

Personal data is stored as individual JSON files in the `db/local/` directory. Each file is named with a unique ID generated using SHA-256 hashing of the timestamp, base64-encoded and truncated to 10 characters.

## License

See LICENSE file for details.
