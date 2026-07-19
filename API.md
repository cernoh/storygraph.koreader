# StoryGraph API — Reverse-Engineered Endpoints

StoryGraph (thestorygraph.com) has no public API. These endpoints were reverse-engineered from browser network traffic (HAR captures, 2026-07-19). They are undocumented and may change without notice.

## Authentication

### Session Cookies

After login, StoryGraph sets two cookies:

- `_storygraph_session` — main session cookie (httpOnly, secure)
- `remember_user_token` — persistent JWT-like token for "remember me"

Both must be sent with every authenticated request.

### CSRF Protection

StoryGraph uses Rails-style CSRF protection:

1. Initial token delivered in `<meta name="csrf-token" content="...">` on the login page
2. Token changes after login; extract new token from subsequent page loads
3. Required in **both**:
   - POST body: `authenticity_token={token}`
   - Request header: `x-csrf-token: {token}`

### Common Headers (Authenticated Requests)

```
Cookie: _storygraph_session=...; remember_user_token=...
x-csrf-token: {csrf_token}
x-requested-with: XMLHttpRequest
Content-Type: application/x-www-form-urlencoded; charset=UTF-8
Origin: https://app.thestorygraph.com
Referer: https://app.thestorygraph.com/books/{book_id}
```

---

## Endpoints

### 1. Login

**Purpose:** Authenticate user and obtain session cookies.

```
POST https://app.thestorygraph.com/users/sign_in
Content-Type: application/x-www-form-urlencoded
```

**Request body:**

| Parameter | Value | Notes |
|-----------|-------|-------|
| `authenticity_token` | CSRF token from login page | Required |
| `user[email]` | user's email | URL-encoded |
| `user[password]` | user's password | URL-encoded |
| `user[remember_me]` | `1` | Enables persistent token |
| `return_to` | empty | Redirect path after login |

**Response:**

- Status: `303 See Other` (redirect to `/`)
- Sets `_storygraph_session` and `remember_user_token` cookies
- Body: empty (redirect)

**Flow:**

1. `GET /users/sign_in` → extract CSRF token from `<meta name="csrf-token">`
2. `POST /users/sign_in` with credentials
3. Follow redirect to `/` → extract new CSRF token from page HTML
4. Use new CSRF token for subsequent requests

---

### 2. ISBN Search (Book Lookup)

**Purpose:** Map ISBN to StoryGraph edition UUID.

```
GET https://app.thestorygraph.com/search?search_term={isbn}&button=
```

**Query parameters:**

| Parameter | Value | Notes |
|-----------|-------|-------|
| `search_term` | ISBN or search query | URL-encoded |
| `button` | empty | Required but unused |

**Response:**

- Status: `200 OK`
- Content-Type: `text/html`
- Body: HTML search results page

**Parsing:**

Extract book UUIDs from links:

```html
<a class="list-option book-list-option" 
   id="search_result_book_{uuid}" 
   href="/books/{uuid}">
  <h1 class="sr-only">{title} by {author}</h1>
  ...
</a>
```

UUID format: `be091845-47e2-4d79-a7f0-09fee0faaf90` (36-char)

**Multiple results:** ISBN search may return multiple editions. Plugin must handle ambiguity (user selection popup or best-match heuristic).

---

### 3. Update Reading Status

**Purpose:** Set reading status (currently reading, finished, etc.).

```
POST https://app.thestorygraph.com/update-status.js?book_id={uuid}&status={status}
Content-Type: application/x-www-form-urlencoded; charset=UTF-8
x-requested-with: XMLHttpRequest
```

**Query parameters:**

| Parameter | Value | Notes |
|-----------|-------|-------|
| `book_id` | edition UUID | Required |
| `status` | status string | See table below |

**Known status values:**

| Status | Meaning |
|--------|---------|
| `currently-reading` | Book in progress |
| `read` | Finished reading |
| `own` | Owned but not reading |
| `want-to-read` | In wishlist (unconfirmed) |
| `did-not-finish` | Stopped reading (unconfirmed) |

**Request body:**

| Parameter | Value | Notes |
|-----------|-------|-------|
| `authenticity_token` | CSRF token | Required |

**Response:**

- Status: `200 OK`
- Content-Type: `text/javascript`
- Body: jQuery JavaScript that updates the UI (can be ignored)

**Example:**

```
POST /update-status.js?book_id=8e4dc319-7f90-41c0-bfa6-030a1c969026&status=currently-reading
Body: authenticity_token=Wg2K22Z3QoVYtyzeqSEWM8BfgU9z8Nb7OlZd8RPyrnPC2OOIRjKJ6RSMr-nGVfkcA9eoQtoDk4tuxQvDJML3mA
```

---

### 4. Update Reading Progress

**Purpose:** Update pages read or percentage complete.

```
POST https://app.thestorygraph.com/update-progress
Content-Type: application/x-www-form-urlencoded; charset=UTF-8
x-requested-with: XMLHttpRequest
```

**Request body:**

| Parameter | Value | Notes |
|-----------|-------|-------|
| `read_status[progress_number]` | integer | Percentage (0-100) or page number |
| `read_status[progress_type]` | `percentage` or `pages` | Unit of progress |
| `read_status[book_num_of_pages]` | integer | Total pages for the edition |
| `read_status[last_reached_percent]` | integer | Previous percentage (for tracking) |
| `read_status[last_reached_pages]` | integer | Previous page count (for tracking) |
| `read_status[progress_minutes]` | empty | Reading time (unused) |
| `book_id` | edition UUID | Required |
| `on_book_page` | `true` or empty | Context flag |
| `commit` | `Save` | Submit button value |
| `return_to_home` | `true` or empty | Redirect flag |
| `authenticity_token` | CSRF token | Required (inferred, not observed) |

**Response:**

- Status: `200 OK`
- Content-Type: `text/javascript`
- Body: jQuery JavaScript that updates progress bar UI (can be ignored)

**Example:**

```
POST /update-progress
Body: read_status[progress_number]=95&read_status[progress_type]=percentage&read_status[book_num_of_pages]=335&read_status[last_reached_percent]=1&read_status[last_reached_pages]=3&book_id=8e4dc319-7f90-41c0-bfa6-030a1c969026&on_book_page=true&commit=Save
```

---

## Implementation Notes

### Response Format

All endpoints return **JavaScript responses** (Rails `.js` format), not JSON. The response body contains jQuery code that updates the UI:

```javascript
$('.progress-tracker-pane[data-book-id=...]').replaceWith("...")
```

**Plugin can ignore the response body.** Only check HTTP status code (200 = success).

### Rate Limiting

No observed rate limiting in HAR captures, but:

- Batch updates (don't push on every page turn)
- Deduplicate (don't push if state unchanged)
- Retry on next action (don't flood on failure)

### Error Handling

- **401/403:** Session expired or CSRF token invalid. Re-login required
- **404:** Book UUID not found or user doesn't have access
- **422:** Validation error (invalid progress value, etc.)
- **500:** Server error. Retry on next action

### Debugging

Enable request/response logging in plugin to capture:

- Request URLs and payloads
- Response status codes
- Cookie values (redact in logs)
- CSRF token extraction

---

## Testing

### Manual Testing with curl

```bash
# 1. Get CSRF token
curl -c cookies.txt -b cookies.txt https://app.thestorygraph.com/users/sign_in | grep csrf-token

# 2. Login
curl -c cookies.txt -b cookies.txt \
  -X POST https://app.thestorygraph.com/users/sign_in \
  -d "authenticity_token=TOKEN&user[email]=EMAIL&user[password]=PASS&user[remember_me]=1"

# 3. Search by ISBN
curl -b cookies.txt "https://app.thestorygraph.com/search?search_term=9780141346458&button="

# 4. Update status
curl -b cookies.txt \
  -X POST "https://app.thestorygraph.com/update-status.js?book_id=UUID&status=currently-reading" \
  -d "authenticity_token=NEW_CSRF_TOKEN" \
  -H "x-requested-with: XMLHttpRequest"

# 5. Update progress
curl -b cookies.txt \
  -X POST https://app.thestorygraph.com/update-progress \
  -d "read_status[progress_number]=95&read_status[progress_type]=percentage&book_id=UUID&commit=Save" \
  -H "x-requested-with: XMLHttpRequest"
```

### Browser HAR Capture

1. Open StoryGraph in browser with DevTools (Network tab)
2. Enable "Preserve log"
3. Perform actions (login, search, update status/progress)
4. Right-click Network tab → "Save all as HAR with content"
5. Parse HAR to extract requests

---

## Changelog

- **2026-07-19:** Initial reverse-engineering from Chrome and Firefox HAR captures
