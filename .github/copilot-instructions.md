# LockedCV-API Copilot Instructions

This file provides guidance to GitHub Copilot when working with the LockedCV API codebase.

## Project Overview

LockedCV is a Ruby Web API that allows accounts to securely share resumes or other personal documents with automatic personal information hiding. It uses the Roda framework with a SQLite data store via Sequel ORM.

- **Ruby version:** 4.0.2 (see `.ruby-version`)
- **Framework:** Roda (lightweight Ruby web framework)

## Commands

### Dependencies and Setup

```bash
bundle install
```

### Running the Application

```bash
puma
```

### Testing

Run all tests:

```bash
bundle exec rake spec
```

### Linting

Run RuboCop:

```bash
bundle exec rubocop
```

## Architecture

### Framework and Routing

- **Roda framework:** Routes are defined via routing tree in controller classes
- **Entry point:** `config.ru` boots the main Roda app (`LockedCV::Api`)
- **Main controller:** `app/controllers/app.rb` contains versioned REST routes (`api/v1/...`)

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

Migration files:

- `db/migrations/001_create_accounts.rb`
- `db/migrations/002_create_attachments.rb`
- `db/migrations/003_create_sensitive_data.rb`
- `db/migrations/004_create_roles.rb`
- `db/migrations/005_account_roles.rb`

### Directory Structure

- `config.ru` — Rack entry point
- `app/controllers/` — Roda controllers with routing logic
- `app/models/` — Sequel models (`Account`, `Attachment`, `SensitiveData`, `Role`)
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
- Error responses use appropriate HTTP status codes (404, 400) with descriptive error messages
- POST success returns 201 status with confirmation message and resource ID

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
