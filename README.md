# LockedCV API

A Ruby web API for the Crypto γ SEC project that allows users to securely share resumes or other personal documents with automatic personal information hiding. Built with Roda framework and SQLite (via Sequel ORM).

## Features

- RESTful API for managing users, attachments, and sensitive data
- SQLite data storage via Sequel ORM
- JSON response format

## Prerequisites

- Ruby 4.0.2 (see `.ruby-version`)
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

### User Endpoints

#### Create User

**POST** `/api/v1/users`

```bash
http -v --json POST localhost:9292/api/v1/users \
  first_name="Jane" \
  last_name="Smith" \
  phone_number="987-654-3210"
```

#### Get User by ID

**GET** `/api/v1/users/:user_id`

```bash
http -v GET localhost:9292/api/v1/users/1
```

### Attachment Endpoints

#### Create Attachment for a User

**POST** `/api/v1/users/:user_id/attachments`

```bash
http -v --json POST localhost:9292/api/v1/users/1/attachments \
  attachment_name="resume_jane.pdf" \
  route="/uploads/resume_jane.pdf"
```

#### Get All Attachments for a User

**GET** `/api/v1/users/:user_id/attachments`

```bash
http -v GET localhost:9292/api/v1/users/1/attachments
```

#### Get Attachment by ID

**GET** `/api/v1/users/:user_id/attachments/:attachment_id`

```bash
http -v GET localhost:9292/api/v1/users/1/attachments/1
```

### Sensitive Data Endpoints

#### Create Sensitive Data for an Attachment

**POST** `/api/v1/users/:user_id/attachments/:attachment_id/sensitive_data`

```bash
http -v --json POST localhost:9292/api/v1/users/1/attachments/1/sensitive_data \
  user_name="Jane Smith" \
  phone_number="987-654-3210" \
  birthday="1990-01-01" \
  email="jane@example.com" \
  address="Taipei" \
  identification_numbers="A123456789"
```

#### Get Sensitive Data by Attachment

**GET** `/api/v1/users/:user_id/attachments/:attachment_id/sensitive_data`

```bash
http -v GET localhost:9292/api/v1/users/1/attachments/1/sensitive_data
```

## Development

### Running Tests

```bash
ruby spec/integration/api_spec.rb
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
│       ├── user.rb          # User DB model
│       ├── attachment.rb    # Attachment DB model
│       └── sensitive_data.rb # SensitiveData DB model
├── config.ru                # Rack configuration
├── db/
│   ├── local/              # Local SQLite database files (gitignored)
│   └── seeds/              # Test seed data
├── spec/                    # Test files
└── .github/
    └── copilot-instructions.md  # AI assistant guidelines
```

## Data Storage

Application data is stored in SQLite database files under `db/local/`.

## License

See LICENSE file for details.
