# Design Decisions

Record of design choices made during the grilling session (2026-07-19).

## 1. Integration Mechanism: Reverse-Engineered HTTP Endpoints

**Decision:** Directly call StoryGraph's undocumented HTTP endpoints.

**Rationale:** StoryGraph has no public API. Community projects have successfully reverse-engineered the same endpoints. The endpoints are clean Rails form submissions — no signed requests, no client-side encryption, no complex auth. Viable for a Lua plugin.

**Rejected alternatives:**
- Playwright/browser automation: KOReader runs on e-ink devices with no Node.js or Chromium runtime. Not feasible on-device.
- Hosted sync service: Would require a third-party server. Out of scope.
- CSV import/export: Manual process. Not automatic.

## 2. Book Identity: ISBN with Title+Author Fallback

**Decision:** Primary lookup via ISBN. If no ISBN in metadata, fall back to title+author search with user selection popup.

**Rationale:** ISBN uniquely identifies an edition. Many EPUBs lack ISBNs (self-published, Project Gutenberg, older editions). Title+author search may return multiple editions (hardcover, paperback, different publishers) — user must select the correct one.

**Tradeoff:** User selection popup adds friction but ensures accuracy. Automatic best-match heuristic risks mapping to the wrong edition.

## 3. Progress Calculation: Percentage × Edition Page Count

**Decision:** Convert KOReader percentage to StoryGraph pages via `percentage × edition_page_count`. Accept inaccuracy.

**Rationale:** KOReader's page count depends on rendering (font size, margins). StoryGraph uses edition-specific page counts. They won't match. User doesn't care about exact pages — just general location.

**Threshold:** 95% KOReader = 100% StoryGraph. Acknowledgements, endnotes, and back matter shouldn't count toward "finished."

## 4. Reading Status Transitions

**Decision:**
- "currently reading" when book opens
- "read" (finished) at 95%+ progress
- Stays "read" even if user reopens the book

**Rationale:** Simple state machine. No "did not finish" or "stopped reading" status — out of scope. Once finished, stays finished unless user manually changes it on StoryGraph's web UI.

**Directionality:** Plugin pushes to StoryGraph, not vice versa. If user changes status on web UI, plugin may overwrite on next sync. Accepted tradeoff for minimal scope.

## 5. Sync Model: Batched on Book Close

**Decision:** Queue actions during reading session. Flush queue on book close. Deduplicate (don't push if state unchanged from last sync).

**Rationale:** Pushing on every page turn would flood StoryGraph and risk rate-limiting. Batching on close is efficient and matches user expectation (sync when done reading).

**Deduplication:** Track last-synced state per book (status + percentage). Only push if changed. Avoids wasteful API calls.

## 6. Failure Handling: Silent Fail + Retry Piggyback

**Decision:**
- Network drop or StoryGraph down → silent fail, queue persists
- Retry piggybacks on next action (e.g., next book close)
- No merge conflicts — just push latest state

**Rationale:** E-ink devices have flaky WiFi. Sync should not block reading or require user intervention. Retry on next action is simple and effective. No conflict resolution needed — latest state wins.

**Edge case:** User reads offline for a week, then syncs. Queue contains multiple actions. Collapse to latest state per book (no need to replay history).

## 7. Authentication: Plaintext Config File

**Decision:** Store credentials in plugin config file (plaintext).

**Rationale:** KOReader runs on personal devices. Threat model is low-risk. Encryption adds complexity (key storage, user prompt) without meaningful security gain. If 2FA is added to StoryGraph, revisit — may need browser-based login.

**Rejected:** Environment variables (KOReader's Lua runtime doesn't expose shell env). Encrypted config (over-engineering for threat model).

## 8. UI: Popup Window (Hardcover Plugin Style)

**Decision:** Popup window for book selection (ISBN fallback) and logs. Similar to hardcover.koreader plugin.

**Rationale:** User needs to select the correct edition when ISBN lookup returns multiple results. Logs help with debugging (optional). Popup is minimal and non-intrusive.

**Rejected:** Full settings UI (out of scope). Background sync with no UI (user can't debug or select books).

## 9. Scope: Minimal Viable Sync

**Decision:** Only sync progress and status. No reviews, ratings, shelves, or other StoryGraph features.

**Rationale:** User wants fast implementation. Scope creep (reviews, annotations, reading time) adds complexity without core value. Can be added later if needed.

**Non-goals:**
- Two-way sync (StoryGraph → KOReader)
- Reading time tracking
- Reviews or ratings
- Shelf management
- Multiple accounts

## 10. Debugging: Optional Logs Window

**Decision:** Logs window in popup for debugging. Not enabled by default.

**Rationale:** Reverse-engineered APIs are fragile. If StoryGraph changes endpoints, user needs a way to diagnose. Logs are low-effort and high-value for troubleshooting.

---

## Open Questions

- **CSRF token lifecycle:** Token changes after login. Plugin must extract new token from page HTML on each session. Implementation detail, not a design decision.
- **Session cookie expiration:** Unknown. Plugin should handle 401/403 by re-login.
- **Rate limiting:** Not observed in testing, but may exist. Batching and deduplication mitigate risk.
- **StoryGraph endpoint stability:** Undocumented APIs can change without notice. Plugin may break. User accepts this risk.

---

## References

- [API.md](API.md) — reverse-engineered endpoints
- [agents.md](agents.md) — agent context
- Grilling session transcript (2026-07-19) — rationale for all decisions
