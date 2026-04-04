# CLAUDE.md

This file provides guidance to copilot Code (copilot.ai/code) when working with code in this repository.

## Project Overview

LockCV is a Ruby Web API that allows users to securely share resumes or other personal documents, such as automatically hiding personal information. It uses the Roda framework with a file-based data store. Ruby 4.0.1.

## Commands

- **Install dependencies:** `bundle install`
- **Run server:** `puma`
- **Run tests:** `ruby spec/api_spec.rb`
- **Lint:** `rubocop`

## Architecture


**Framework:** Roda (lightweight Ruby web framework) — routes defined via `routing` tree in controller classes.

**Structure:**

- `config.ru` — Rack entry point, boots `LockCV::Api`
- `app/controllers/app.rb` — Main Roda app with versioned REST routes (`api/v1/...`)
- `app/models/` — Domain models (e.g., `PersonalData`) with file-based persistence
- `db/local/` — File store directory (gitignored); each record is a `.txt` file containing JSON
- `db/seeds/` — YAML seed data for tests
- `spec/` — Minitest specs using `Rack::Test`

**Module namespace:** `LockCV` — all app classes live under this module.

**Data store:** Models persist as individual JSON files in `db/local/`. IDs are generated via SHA-256 hash of timestamp, base64-encoded, truncated to 10 chars. The store directory is created on app startup via `PersonalData.setup`.

**Test conventions:** Tests use Minitest with `minitest-rg` for colored output. The `before` block wipes `db/local/*.txt` before each test. Test data comes from `db/seeds/course_seeds.yml`. Tests are labeled HAPPY/SAD to indicate success/failure paths.

## Style

RuboCop with `rubocop-minitest` plugin. Target Ruby version 4.0. New cops enabled. `Metrics/BlockLength` excluded for specs.

All documentation markdown files must be kept lint-free (no trailing whitespace, consistent heading levels, blank lines around blocks, etc.).