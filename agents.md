# StoryGraph KOReader Plugin — Agent Context

KOReader Lua plugin syncing reading progress/status to StoryGraph via reverse-engineered HTTP endpoints. No public API. Design complete, implementation not started.

**Stack:** Lua 5.1, KOReader, e-ink devices (Kindle/Kobo/PocketBook/Android)

**Files:** `main.lua` (entry), `api.lua` (HTTP client), `config.lua` (settings), `sync.lua` (queue/retry)

## API (see API.md)

- **Login:** POST `/users/sign_in` (form auth + CSRF)
- **ISBN lookup:** GET `/search?search_term={isbn}&button=` → parse HTML for book UUID
- **Status:** POST `/update-status.js?book_id={uuid}&status={status}` (values: `currently-reading`, `read`, `own`)
- **Progress:** POST `/update-progress` (percentage, page count, CSRF)

## Invariants

1. CSRF token in body (`authenticity_token`) AND header (`x-csrf-token`); changes after login
2. Session cookies (`_storygraph_session`, `remember_user_token`) required for all requests
3. 95% KOReader = 100% StoryGraph (end matter excluded)
4. Status `read` = finished (not "finished")
5. Endpoints return JavaScript (jQuery), not JSON — ignore body, check HTTP status
6. Deduplicate: don't push if state unchanged from last sync
7. Silent fail on network error; retry piggybacks on next action

## Conventions

Follow KOReader plugin patterns (see hardcover.koplugin). No abstractions. Credentials in plaintext config. Errors: silent fail + log, popup only for critical failures. No unit tests (device-dependent).

## Gotchas

- Many EPUBs lack ISBN → title+author search → user selection popup
- KOReader page count ≠ StoryGraph page count → use percentage × edition pages
- ISBN search may return multiple editions → user must select
- `last_reached_percent` field tracks previous state in progress updates
