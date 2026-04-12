# Copilot Instructions

This file provides guidance to GitHub Copilot when working with the LockedCV API codebase.

## Project Overview

LockedCV is a Ruby Web API that allows users to securely share resumes or other personal documents with automatic personal information hiding. It uses the Roda framework with a file-based data store.

- **Ruby version:** 4.0.1 (see `.ruby-version`)
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
ruby spec/api_spec.rb
```

### Linting

Run RuboCop:

```bash
rubocop
```

## Architecture

### Framework and Routing

- **Roda framework:** Routes are defined via routing tree in controller classes
- **Entry point:** `config.ru` boots the main Roda app (`LockedCV::Api`)
- **Main controller:** `app/controllers/app.rb` contains versioned REST routes (`api/v1/...`)

### Module Namespace

All application classes live under the `LockedCV` module namespace.

### Data Persistence

**File-based store:**

- Models persist as individual JSON files in `db/local/`
- Each record is a `.txt` file containing JSON data
- Store directory: `db/local/` (gitignored)
- The store directory is created on app startup via `PersonalData.setup`

**ID generation:**

- IDs are generated via SHA-256 hash of timestamp
- Base64-encoded and truncated to 10 characters
- Implementation in `PersonalData#new_id`

### Relational Schema (`db/migrations`)

Current schema implemented in migrations:

1. `files`
   - `id` (String, PK)
   - `file_name` (String)
   - `route` (String)
   - `update_time` (DateTime)
   - `user_id` (String, FK -> `users.id`)
   - Unique constraint: `[:user_id, :file_name]`
2. `sensitive_data`
   - `id` (String, PK)
   - `user_name` (String)
   - `phone_number` (String)
   - `birthday` (Date)
   - `email` (String)
   - `address` (String)
   - `identification_numbers` (String)
   - `file_id` (String, FK -> `files.id`)
   - Unique constraint: `[:file_id]`
3. `users` (cause ohters tables reference it)
   - `id` (String, PK)
   - `first_name` (String)
   - `last_name` (String)
   - `phone_number` (String)

Migration files:

- `db/migrations/001_create_files.rb`
- `db/migrations/002_create_sensitive_data.rb`
- `db/migrations/003_user.rb`

### Directory Structure

- `config.ru` — Rack entry point
- `app/controllers/` — Roda controllers with routing logic
- `app/models/` — Domain models (e.g., `PersonalData`) with file-based persistence
- `db/local/` — File store directory (gitignored)
- `db/seeds/` — YAML seed data for tests
- `spec/` — Minitest specs using `Rack::Test`

### Models

- Models implement `save`, `find(id)`, and `all` methods
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
- **Test data:** Seed data in `db/seeds/course_seeds.yml`
- **Test labels:** Tests are labeled HAPPY/SAD to indicate success/failure paths
- **Setup:** The `before` block wipes `db/local/*.txt` before each test

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

- Uses `rbnacl` gem for cryptographic operations (SHA-256 hashing)
- Personal data handling for secure resume/document sharing
