# LockedCV API

A Ruby web API for the Crypto γ SEC project that allows accounts to securely share resumes or other personal documents with automatic personal information hiding. Built with Roda framework and SQLite (via Sequel ORM).

## Features

- RESTful API for managing accounts, attachments, and sensitive data
- SQLite data storage via Sequel ORM
- PII protection for account email/phone via encrypted (`*_secure`) + searchable hash (`*_hash`) columns
- Role foundation with `roles` and `accounts_roles` (many-to-many)
- PDF attachment upload, masked-text preview, and masked PDF export support
- Admin-only system role assignment and account listing
- Token-based authorization with `Authorization: Bearer <TOKEN>`
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

3. Copy local secrets:

```bash
cp config/secrets-example.yml config/secrets.yml
```

4. Generate local crypto keys and paste them into `config/secrets.yml`:

```bash
bundle exec rake newkey:db
bundle exec rake newkey:hash
bundle exec rake newkey:msg
```

5. Prepare the local database:

```bash
bundle exec rake db:migrate
bundle exec rake db:seed
```

6. Bootstrap the first admin account when needed:

```bash
bundle exec rake db:bootstrap_admin USERNAME=admin EMAIL=admin@example.com
```

The task ensures the `admin` and `member` system roles exist, creates the
account if it does not already exist, and grants the `admin` role. `EMAIL` is
required when creating a new account; when the account already exists, the task
does not read or update its email.

## Running the Application

Start the API development server:

```bash
bundle exec rake run:dev
```

The API will be available at `http://localhost:9000`

## API Endpoints

### Root Endpoint

**GET** `/`

Returns API status message.

```bash
http -v GET localhost:9000/
```

Response:
```json
{
  "message": "LockedCV API up at /api/v1"
}
```

### Authentication Endpoints

#### Authenticate Account

**POST** `/api/v1/auth/authenticate`

```bash
http -v --json POST localhost:9000/api/v1/auth/authenticate \
  username="jane_smith" \
  password="my-secret-password"
```

Successful authentication returns safe account information for the client
session, including account ID, username, email, roles, and an `auth_token`.
Invalid credentials return `403` with a JSON error message.

Use the returned token on protected API requests:

```bash
http -v GET localhost:9000/api/v1/account \
  Authorization:"Bearer <auth_token>"
```

Missing, invalid, or expired tokens return `401`. Authenticated callers without
permission return `403`.

### Account Endpoints

#### Get Current Account

**GET** `/api/v1/account`

```bash
http -v GET localhost:9000/api/v1/account \
  Authorization:"Bearer <auth_token>"
```

#### Update Current Account

**PUT** `/api/v1/account`

```bash
http -v --json PUT localhost:9000/api/v1/account \
  Authorization:"Bearer <auth_token>" \
  email="jane.updated@example.com" \
  phone_number="987-654-3210" \
  first_name="Jane" \
  last_name="Smith" \
  birthday="1990-01-01" \
  address="Taipei" \
  identification_numbers="A123456789"
```

#### Change Current Account Password

**PUT** `/api/v1/account/password`

```bash
http -v --json PUT localhost:9000/api/v1/account/password \
  Authorization:"Bearer <auth_token>" \
  current_password="my-secret-password" \
  password="my-new-secret-password"
```

The current password must be correct before the password is replaced.

#### List Accounts

**GET** `/api/v1/accounts`

```bash
http -v GET localhost:9000/api/v1/accounts \
  Authorization:"Bearer <admin_auth_token>"
```

Only accounts with the `admin` system role can list accounts.

For a production database with no admin yet, use:

```bash
bundle exec rake db:bootstrap_admin USERNAME=admin EMAIL=admin@example.com
```

#### Create Account

**POST** `/api/v1/accounts`

```bash
http -v --json POST localhost:9000/api/v1/accounts \
  username="jane_smith" \
  email="jane@example.com" \
  phone_number="987-654-3210" \
  password="my-secret-password"
```

#### Legacy Get Account by ID

**GET** `/api/v1/accounts/:account_id`

```bash
http -v GET localhost:9000/api/v1/accounts/<account_uuid> \
  Authorization:"Bearer <auth_token>"
```

This legacy account-scoped route remains for compatibility and still requires
the path account to match the Bearer token owner.

#### Legacy Update Account

**PUT** `/api/v1/accounts/:account_id`

```bash
http -v --json PUT localhost:9000/api/v1/accounts/<account_uuid> \
  Authorization:"Bearer <auth_token>" \
  email="jane.updated@example.com" \
  phone_number="987-654-3210" \
  first_name="Jane" \
  last_name="Smith" \
  birthday="1990-01-01" \
  address="Taipei" \
  identification_numbers="A123456789"
```

This legacy account-scoped route remains for compatibility and still requires
the path account to match the Bearer token owner.

#### Legacy Change Account Password

**PUT** `/api/v1/accounts/:account_id/password`

```bash
http -v --json PUT localhost:9000/api/v1/accounts/<account_uuid>/password \
  Authorization:"Bearer <auth_token>" \
  current_password="my-secret-password" \
  password="my-new-secret-password"
```

The current password must be correct before the password is replaced.

This legacy account-scoped route remains for compatibility and still requires
the path account to match the Bearer token owner.

#### Delete Account

**DELETE** `/api/v1/accounts/:account_id`

```bash
http -v DELETE localhost:9000/api/v1/accounts/<target_account_uuid> \
  Authorization:"Bearer <admin_auth_token>"
```

Only accounts with the `admin` system role can delete accounts. Admins cannot
delete their own account.

#### Assign System Role

**PUT** `/api/v1/accounts/:username/system_roles/:role_name`

```bash
http -v --json PUT localhost:9000/api/v1/accounts/jane_smith/system_roles/member \
  Authorization:"Bearer <admin_auth_token>"
```

Only accounts with the `admin` system role can assign system roles.

### Attachment Endpoints

#### Upload Attachment File for an Account

**POST** `/api/v1/accounts/:account_id/attachments/upload`

```bash
http -v --form POST localhost:9000/api/v1/accounts/<account_uuid>/attachments/upload \
  Authorization:"Bearer <auth_token>" \
  file@/path/to/resume.pdf
```

Only PDF uploads are currently supported. Uploaded files are stored under
`storage/`, and attachment metadata is saved in the database.

#### Create Attachment for an Account

**POST** `/api/v1/accounts/:account_id/attachments`

```bash
http -v --json POST localhost:9000/api/v1/accounts/<account_uuid>/attachments \
  Authorization:"Bearer <auth_token>" \
  attachment_name="resume_jane.pdf" \
  route="accounts/<account_uuid>/resume_jane.pdf"
```

#### Get All Attachments for an Account

**GET** `/api/v1/attachments`

```bash
http -v GET localhost:9000/api/v1/attachments \
  Authorization:"Bearer <auth_token>"
```

This is the token-scoped endpoint used by the App. The API finds the requesting
account from the Bearer token.

#### Legacy Get All Attachments for an Account

**GET** `/api/v1/accounts/:account_id/attachments`

```bash
http -v GET localhost:9000/api/v1/accounts/<account_uuid>/attachments \
  Authorization:"Bearer <auth_token>"
```

This legacy account-scoped route remains for compatibility and still requires
the path account to match the Bearer token owner.

#### Get Attachment by ID

**GET** `/api/v1/accounts/:account_id/attachments/:attachment_id`

```bash
http -v GET localhost:9000/api/v1/accounts/<account_uuid>/attachments/1 \
  Authorization:"Bearer <auth_token>"
```

#### Get Masked Attachment Text

**GET** `/api/v1/accounts/:account_id/attachments/:attachment_id/masked_text`

```bash
http -v GET localhost:9000/api/v1/accounts/<account_uuid>/attachments/1/masked_text \
  Authorization:"Bearer <auth_token>"
```

Extracts PDF text, detects sensitive values, and returns masked text preview
data for the attachment.

#### Export Masked PDF Attachment

**POST** `/api/v1/accounts/:account_id/attachments/:attachment_id/masked_attachments`

```bash
http -v --json POST \
  localhost:9000/api/v1/accounts/<account_uuid>/attachments/1/masked_attachments \
  Authorization:"Bearer <auth_token>"
```

Creates a generated masked PDF file and saves masked output metadata. This is a
text-based visual masking approximation, not a formal PDF redaction engine.

### Sensitive Data Endpoints

#### Create Sensitive Data for an Attachment

**POST** `/api/v1/accounts/:account_id/attachments/:attachment_id/sensitive_data`

```bash
http -v --json POST localhost:9000/api/v1/accounts/<account_uuid>/attachments/1/sensitive_data \
  Authorization:"Bearer <auth_token>" \
  first_name="Jane" \
  last_name="Smith" \
  phone_number="987-654-3210" \
  birthday="1990-01-01" \
  email="jane@example.com" \
  address="Taipei" \
  identification_numbers="A123456789"
```

#### Get Sensitive Data by Attachment

**GET** `/api/v1/accounts/:account_id/attachments/:attachment_id/sensitive_data`

```bash
http -v GET localhost:9000/api/v1/accounts/<account_uuid>/attachments/1/sensitive_data \
  Authorization:"Bearer <auth_token>"
```

## Development

### Running Tests

```bash
bundle exec rake spec
```

### Linting

Run RuboCop to check code style:

```bash
bundle exec rake style
```

## Project Structure

```
.
├── app/
│   ├── controllers/
│   │   ├── app.rb          # Main Roda app with API route dispatch
│   │   ├── accounts.rb     # Account-scoped API routes
│   │   ├── auth.rb         # Authentication API routes
│   │   └── http_request.rb # Request body and TLS/SSL helpers
│   ├── lib/                # Crypto and password key-stretching helpers
│   ├── models/
│       ├── account.rb       # Account DB model
│       ├── attachment.rb    # Attachment DB model
│       ├── masked_attachment.rb # Masked PDF output DB model
│       ├── masked_item.rb   # Masked value metadata DB model
│       ├── role.rb          # Role DB model
│       └── sensitive_data.rb # SensitiveData DB model
│   └── services/            # Application services for API behavior
├── config/                  # Environment and secrets configuration
├── config.ru                # Rack configuration
├── db/
│   ├── migrations/         # Sequel migrations
│   ├── local/              # Local SQLite database files (gitignored)
│   └── seeds/              # Test seed data
├── docs/
│   └── schema.md           # Current database schema notes
├── spec/                    # Test files
├── storage/                 # Uploaded attachment files
└── .github/
    └── copilot-instructions.md  # AI assistant guidelines
```

## Data Storage

Application data is stored in SQLite database files under `db/local/`. Uploaded
and generated PDF files are stored under `storage/uploads/`.

## License

See LICENSE file for details.
