# LockedCV-API Copilot Instructions

This file provides guidance to GitHub Copilot when working with the LockedCV API codebase.

## Startup Context for AI Assistants

Before making changes, read:

1. `README.md`
2. `.github/copilot-instructions.md`
3. `local.md` if it exists in the repo root

`local.md` is intentionally gitignored. It is for local handoff notes such as
current task status, user preferences, deployment reminders, or decisions not
ready to commit.

## Project Overview

LockedCV is a Ruby Web API that allows accounts to securely share resumes or other personal documents with automatic personal information hiding. It uses the Roda framework with a SQLite data store via Sequel ORM.

- **Ruby version:** 4.0.2 (see `.ruby-version`)
- **Framework:** Roda (lightweight Ruby web framework)

## Commands

### Dependencies and Setup

```bash
bundle install
```

Masked PDF export also needs a Python environment with `pdfplumber` and
`reportlab`. Use `PYTHON_BIN` when the correct executable is not `python3`.
This dependency is not managed by Bundler.

### Running the Application

```bash
bundle exec rake run:dev
```

The development server runs on port `9000`.

### Testing

Run all tests:

```bash
bundle exec rake spec
```

When migrations change, run:

```bash
bundle exec rake db:migrate
```

### Linting

Run RuboCop:

```bash
bundle exec rake style
```

## Architecture

### Framework and Routing

- **Roda framework:** Routes are defined via routing tree in controller classes
- **Entry point:** `config.ru` boots the main Roda app (`LockedCV::Api`)
- **Main controller:** `app/controllers/app.rb` contains versioned REST routes (`api/v1/...`)
- **Route files:** `app/controllers/accounts.rb` and `app/controllers/auth.rb`
  provide the current API routes through Roda `multi_route`

### Module Namespace

All application classes live under the `LockedCV` module namespace.

### Data Persistence

Application data is stored in SQLite database files under `db/local/` (gitignored).

### Relational Schema (`db/migrations`)

Current schema implemented in migrations:

1. `accounts`
   - `id` (UUID, PK)
   - `username` (String, unique, plaintext)
   - `email_secure` (String, encrypted)
   - `email_hash` (String, deterministic hash, unique)
   - `phone_number_secure` (String, encrypted, optional)
   - `phone_number_hash` (String, deterministic hash, optional, unique)
   - `first_name_secure`, `last_name_secure` (String, encrypted, optional)
   - `birthday_secure`, `address_secure`,
     `identification_numbers_secure` (String, encrypted, optional)
   - `password_digest` (String)
   - `created_at`, `updated_at` (DateTime)
2. `attachments`
   - `id` (Integer, PK)
   - `attachment_name` (String)
   - `route` (String, unique)
   - `account_id` (UUID, FK -> `accounts.id`)
   - `created_at`, `updated_at` (DateTime)
   - Unique constraint: `[:account_id, :attachment_name]`
3. `sensitive_data`
   - `id` (Integer, PK)
   - `first_name_secure`, `last_name_secure` (String)
   - `phone_number_secure`, `birthday_secure` (String)
   - `email_secure`, `address_secure`, `identification_numbers_secure` (String)
   - `attachment_id` (Integer, FK -> `attachments.id`, unique)
   - `created_at`, `updated_at` (DateTime)
4. `roles`
   - `id` (Integer, PK)
   - `name` (String, unique)
   - `created_at`, `updated_at` (DateTime)
5. `accounts_roles`
   - `account_id` (UUID, FK -> `accounts.id`)
   - `role_id` (Integer, FK -> `roles.id`)
   - Composite PK: `[:account_id, :role_id]`
6. `masked_attachments`
   - `id` (Integer, PK)
   - `attachment_id` (Integer, FK -> `attachments.id`)
   - `attachment_name` (String)
   - `route` (String, unique)
   - `created_at`, `updated_at` (DateTime)
7. `masked_items`
   - `id` (Integer, PK)
   - `masked_attachment_id` (Integer, FK -> `masked_attachments.id`)
   - `field_name` (String)
   - `value_secure` (String, encrypted)
   - `is_masked` (Boolean)
   - `source` (String: `sensitive_data`, `regex`, or `manual`)
   - `created_at`, `updated_at` (DateTime)

Migration files:

- `db/migrations/001_create_accounts.rb`
- `db/migrations/002_create_attachments.rb`
- `db/migrations/003_create_sensitive_data.rb`
- `db/migrations/004_create_roles.rb`
- `db/migrations/005_account_roles.rb`
- `db/migrations/006_create_masked_attachments.rb`
- `db/migrations/007_create_masked_items.rb`

### Directory Structure

- `config.ru` — Rack entry point
- `app/controllers/` — Roda controllers with routing logic
- `app/lib/` — crypto and password key-stretching helpers
- `app/models/` — Sequel models (`Account`, `Attachment`,
  `MaskedAttachment`, `MaskedItem`, `SensitiveData`, `Role`)
- `app/services/` — application services for account, role, attachment, PDF,
  and masking behavior
- `docs/schema.md` — schema notes and ERD
- `storage/` — uploaded attachment files
- `db/local/` — Local SQLite database files (gitignored)
- `db/seeds/` — YAML seed data for tests
- `spec/` — Minitest specs using `Rack::Test`

### Models

- Models use Sequel ORM associations and persistence helpers
- All models include `to_json` for API responses
- Response format includes `type` field identifying the resource type

### API Responses

- All responses use `Content-Type: application/json`
- Success responses return JSON objects with relevant data
- Error responses use appropriate HTTP status codes (`400`, `401`, `403`,
  `404`, `500`) with descriptive error messages
- POST success returns 201 status with confirmation message and resource ID

### Current API Surface

- `POST /api/v1/auth/authenticate` authenticates an account and returns safe
  session data plus `auth_token` for the Web App.
- `POST /api/v1/auth/register` checks registration availability and sends a
  Mailgun verification email using the `verification_url` supplied by the App.
  The API does not create or persist registration tokens.
- Protected routes use `Authorization: Bearer <TOKEN>`.
- `GET /api/v1/account` returns the current account from the token.
- `PUT /api/v1/account` updates the current account from the token.
- `PUT /api/v1/account/password` changes the current account password.
- `GET /api/v1/attachments` lists the current account attachments from the
  token.
- `GET /api/v1/accounts` lists accounts for admins; caller identity comes from
  the Bearer token.
- `POST /api/v1/accounts/registration/check` checks whether username/email are
  available before the App requests a verification email.
- `POST /api/v1/accounts` creates a basic account. Account detail verification
  still needs to be strengthened.
- `GET /api/v1/accounts/:account_id`, `PUT /api/v1/accounts/:account_id`, and
  `PUT /api/v1/accounts/:account_id/password` are legacy account-scoped routes;
  they require the path account to match the Bearer token owner.
- `DELETE /api/v1/accounts/:account_id` deletes an account and requires an
  admin Bearer token. The path account is the target. Admins cannot delete
  their own account.
- `PUT /api/v1/accounts/:username/system_roles/:role_name` assigns a system
  role and requires an admin Bearer token. The path username is the target.
- `POST /api/v1/attachments/upload` uploads a PDF for the Bearer token account
  and creates attachment metadata.
- `DELETE /api/v1/attachments/:attachment_id` deletes an attachment owned by
  the Bearer token account, including dependent metadata, original file, and
  masked PDF files.
- `GET /api/v1/attachments/:attachment_id` returns one attachment owned by the
  Bearer token account.
- `GET /api/v1/attachments/:attachment_id/masked_text` extracts and masks PDF
  text for an attachment owned by the Bearer token account.
- `POST /api/v1/attachments/:attachment_id/masked_attachments` exports a
  generated masked PDF and records masked output metadata for an attachment
  owned by the Bearer token account.
- `GET/POST /api/v1/accounts/:account_id/attachments/:attachment_id/sensitive_data`
  reads or creates sensitive data for an attachment.

### Roda Routing

- Use `routing.on` for path segments (e.g., `routing.on 'api'`)
- Use `routing.get`, `routing.post` for HTTP methods
- Use `routing.get String do |id|` to capture URL parameters
- Use `routing.halt` with status code and JSON for error responses
- Rescue `StandardError` for not-found resources and return 404

## Code Conventions

### Testing

- **Framework:** Minitest with `minitest-rg` for colored output
- **Test data:** Seed data in `db/seeds/*.yml`
- **Test labels:** Tests are labeled HAPPY/SAD to indicate success/failure paths
- **Setup:** Tests clear database tables before each test

### Code Style

- **Linter:** RuboCop with `rubocop-minitest` plugin
- **Target Ruby version:** 4.0
- **New cops:** Enabled by default
- **Exclusions:** `Metrics/BlockLength` is excluded for spec files

### Documentation

All markdown files must be kept lint-free:

- No trailing whitespace
- Consistent heading levels
- Blank lines around blocks

## Security

- Uses `rbnacl` gem for cryptographic operations (encryption + keyed HMAC-SHA256 hashing)
- Personal data handling for secure resume/document sharing
- Masked PDF export is a text-based visual masking approximation for
  text-based PDFs, not a formal PDF redaction engine. It shells out to the
  Python pdfplumber/reportlab processor and writes temporary payload JSON under
  `tmp/` during processing.
- API enforces TLS/SSL through `HttpRequest#secure?`; local development uses
  `SECURE_SCHEME: HTTP`, while production should use `SECURE_SCHEME: HTTPS`.
- Mailgun settings (`MAILGUN_API_KEY`, `MAILGUN_DOMAIN`,
  `MAILGUN_FROM_EMAIL`, `MAILGUN_FROM_NAME`) are required for development
  registration emails. Test can use dummy values because specs stub Mailgun.
- Do not expose plaintext passwords, password digests, encrypted columns, or
  lookup hashes in API responses.
- Missing, invalid, or expired auth tokens return `401`; authenticated callers
  without permission return `403`; missing resources return `404` unless a route
  intentionally hides existence.
