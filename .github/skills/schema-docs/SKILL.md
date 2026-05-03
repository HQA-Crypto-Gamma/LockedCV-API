---
name: schema-docs
description: Use when updating LockedCV API database schema documentation after migrations, Sequel model association changes, role model changes, authentication response changes, or security-related persistence changes.
---

# Schema Docs Skill

Use this skill when a change affects database structure, model associations,
role semantics, authentication payloads, or persistence security behavior.

## Update Workflow

1. Read `db/migrations/` to confirm the migrated schema.
2. Read affected models in `app/models/` for Sequel associations, getters,
   setters, and response behavior.
3. Check `db/seeds/` for canonical role names and sample data assumptions.
4. Update `docs/schema.md`.
5. Keep the Mermaid `erDiagram` aligned with the current migrated schema.
6. Document security semantics, not just column names:
   - encrypted `*_secure` fields
   - keyed lookup `*_hash` fields
   - password digest format
   - role tables and join tables
   - authentication response fields
   - deferred authorization assumptions

## Documentation Rules

- Keep Markdown concise and lint-friendly.
- Prefer current design facts over implementation history.
- If role or authorization behavior is not implemented yet, mark it as
  deferred instead of implying it is enforced.
- Keep API response notes aligned with integration specs.
- Do not include secrets, generated database files, or local machine paths.

## Validation

Run the project checks after documentation changes when practical:

```bash
bundle exec rake spec
bundle exec rubocop --cache false .
```
