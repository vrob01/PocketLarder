# PocketLarder Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The PocketLarder server: a Go JSON API with invite pairing, device tokens, offline-safe sync, server-enforced list privacy, a CLI for bootstrap and backup, and a container image.

**Architecture:** One static Go binary (`server/`) with all logic in package `server/internal/larder` and a three-line `main.go`. SQLite through a pure-Go driver, schema upgrades by `PRAGMA user_version`. Clients sync by POSTing their queued operations to `/v1/sync`. The server applies them in one transaction and returns a full snapshot of everything that member may see.

**Tech Stack:** Go 1.27.3+ (`go 1.27.3`), `net/http` routing patterns, `log/slog`, `modernc.org/sqlite` v1.61.0, Docker (`FROM scratch`), Caddy (example only).

**Spec:** `docs/superpowers/specs/2026-10-27-pocketlarder-design.md`

**Status:** approved by the owner on 2026-10-27, together with the spec and its mockups. Execution: through the software factory, one GitHub issue per task, run one at a time in order, because each task builds on the merged PR of the one before.

This is plan 1 of 3. Plan 2 covers the iOS app, its Mac setup guide (kept out of the repo) and the GitHub Actions iOS checks. Plan 3 covers OIDC on both the server and the app. Plan 2 is written against `server/API.md`, which this plan produces.

## Global Constraints

- Single static binary: `CGO_ENABLED=0`. Two dependencies: `modernc.org/sqlite` for SQLite, and `golang.org/x/text` for name normalisation and lookalike detection (Task 2). Any other dependency needs a one-line justification in the commit message.
- The factory machine has Go 1.24.4. `go.mod` says `go 1.27.3`, the latest release on 2026-10-27, and the local `go` downloads that toolchain on its own (GOTOOLCHAIN=auto). The reason: the driver requires 1.26, and 1.24 no longer gets security fixes.
- Plain HTTP behind a TLS-terminating reverse proxy. Versioned JSON API under `/v1` only: no HTML, no static files, no CORS headers.
- The API must not assume iOS (Android may come later).
- Invites: single-use, high-entropy, expire after 24 hours. Device tokens: random, at least 256 bits, no time expiry.
- No reusable secrets at rest: invites and tokens are stored only as SHA-256 hashes and compared with `crypto/subtle.ConstantTimeCompare`.
- Every request except invite redemption needs a valid device token. Redemption is rate-limited.
- Validate every input at the boundary (types, lengths, ownership). Limit request sizes.
- The server enforces list privacy. A hidden list and its entries (including recently bought) are never sent to another member's device.
- Tokens, invite codes and request bodies never appear in logs or error messages.
- Container: non-root, read-only root filesystem, the data volume as the only writable path.
- Hard requirement: a sync never undoes a local change. Server side, this means operations are idempotent by `op_id`, and the snapshot is built after the batch in the same transaction.
- No passwords, no web UI, no push, one household per server.
- Every task touches auth, sync or the API, so every task's review includes a security review.

## Decisions this plan makes

The spec left these to the builder. They fix the API that plan 2 builds against.

- **Full snapshot sync.** No deltas or tombstones, so revoking visibility (a hidden list) falls out for free. `shortcut: full snapshot each sync, switch to deltas if a household's snapshot grows past ~1 MB`.
- **Operations, not resources.** Every change a member makes is an op in the sync queue, including privacy. Only pairing, sign-out and admin actions are plain endpoints, because they need a connection anyway.
- **"Unfiled" is a display rule.** An entry shows under "Not filed yet" when it has no item, no store, or its item has no placement in its store. Deleting a store, category or item therefore never rewrites or loses entries. Foreign keys set the references to NULL, and the entry falls back to "Not filed yet".
- **Entries always keep `text`** (the item name at the time they were added), so deleting an item never loses the name.
- **An invite is always bound to a member.** Inviting a new member creates the member and their personal list right away. Unredeemed new members show up in the admin area, where they can be removed.
- **Names are compared after trimming and collapsing whitespace, ignoring case and lookalike characters** (`nameKey`, Task 2). Item and member names are unique on that key.
- **List colors** are tokens the app maps to real colors: `red orange yellow green teal blue purple pink gray`.
- **Recently bought:** the newest 50 bought entries per list are synced. Old bought rows stay in the database. `shortcut: bought entries are never pruned, add pruning if the database grows noticeably`.
- **Timestamps** are stored as unix seconds and sent as RFC 3339 UTC without fractions (`2026-10-27T10:00:00Z`).

## Review Focus

1. **A batch re-sent after a lost response** must not bring back an entry deleted in the meantime (items popping back). Test: Task 4, `TestResentBatchDoesNotResurrect`.
2. **The same name spelled differently by two members** ("Milk" vs " milk ") must end on one catalog item, and renaming onto a taken name must be refused. Tests: Task 4, `TestFilingLinksToExistingItemIgnoringCase`, and Task 5, `TestItemRenameConflict`.
3. **A list that becomes read-only or hidden while another member has queued offline edits to it:** the edits are refused, and the list disappears from that member's next snapshot. Test: Task 4, `TestPrivacyEnforced`.
4. **Deleting a store or category that still has open entries:** every entry survives and falls back to "Not filed yet". Tests: Task 5, `TestDeletingStoreKeepsEntries` and `TestDeletingCategoryKeepsEntries`.
5. **The last admin demoting or removing themselves** must be refused, or nobody could invite again without shell access. Tests: Task 2, `TestLastAdminGuard`, and Task 3, `TestHTTPLastAdminGuard`.

---

### Task 1: Module, database and licenses

**Files:**
- Create: `server/go.mod`, `server/go.sum`
- Create: `server/internal/larder/db.go`
- Test: `server/internal/larder/db_test.go`, `server/internal/larder/helpers_test.go`
- Create: `server/LICENSE` (AGPL-3.0), `ios/LICENSE` (MPL-2.0)
- Replace: `LICENSE`

**Interfaces:**
- Produces: `func openDB(path string) (*sql.DB, error)`. It opens `file:<path>` with the DSN pragmas `foreign_keys(1)`, `busy_timeout(5000)`, `journal_mode(WAL)` and `temp_store(MEMORY)` (the pragmas are in the DSN so every pooled connection gets them, and `temp_store` matters because the root filesystem is read-only). It then calls `SetMaxOpenConns(1)` and runs pending `migrations`. A database whose `user_version` is greater than `len(migrations)` was written by a newer binary: `openDB` checks this before any migration, leaves the database unchanged, closes the handle and returns an error naming both versions. `shortcut: one connection serialises all access, fine for a household, revisit if requests queue`.
- Produces: `var migrations []string`. Element *i* upgrades the schema to version *i+1*. Each element runs in a transaction that sets `PRAGMA user_version`.
- Produces: `func withTx(db *sql.DB, fn func(*sql.Tx) error) error`, which commits on nil and rolls back otherwise.
- Produces (tests): `func testDB(t *testing.T) *sql.DB` (opens a database in `t.TempDir()`) and `func ptr[T any](v T) *T`.

- [ ] **Step 1: Create the module**

```bash
mkdir -p server/internal/larder && cd server
go mod init github.com/vrob01/pocketlarder/server
go mod edit -go=1.27.3
go get modernc.org/sqlite@v1.61.0
```

- [ ] **Step 2: Write the failing tests** in `db_test.go`

```go
func TestOpenDBMigratesOnce(t *testing.T) {
	path := filepath.Join(t.TempDir(), "p.db")
	db, err := openDB(path) // first open creates the schema
	if err != nil { t.Fatal(err) }
	db.Close()
	db, err = openDB(path) // second open must not re-run migration 1
	if err != nil { t.Fatal(err) }
	var v int
	db.QueryRow("PRAGMA user_version").Scan(&v)
	if v != len(migrations) { t.Fatalf("user_version = %d, want %d", v, len(migrations)) }
}

func TestDeletingStoreNullsReferencesAndKeepsEntries(t *testing.T) {
	db := testDB(t)
	// insert: store s; category c in s; item i (default_store_id s); placement (i,s,c);
	// member m with personal list l; entry e (list l, item i, store s)
	// DELETE FROM stores WHERE id = s
	// want: categories and placements gone; items.default_store_id IS NULL;
	//       entry e still exists with store_id IS NULL
}
```

- [ ] **Step 3: Run** `cd server && go test ./...`. Expected: FAIL, `undefined: openDB`.

- [ ] **Step 4: Implement `openDB`, `withTx` and migration 1** in `db.go`. Migration 1 is exactly this schema:

```sql
CREATE TABLE members (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  name_key TEXT NOT NULL UNIQUE,
  is_admin INTEGER NOT NULL DEFAULT 0,
  privacy TEXT NOT NULL DEFAULT 'open' CHECK (privacy IN ('open','readonly','hidden')),
  created_at INTEGER NOT NULL
);
CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  member_id TEXT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  secret_hash BLOB NOT NULL,
  created_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL
);
CREATE TABLE invites (
  id TEXT PRIMARY KEY,
  member_id TEXT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  secret_hash BLOB NOT NULL,
  expires_at INTEGER NOT NULL,
  used_at INTEGER
);
CREATE TABLE lists (
  id TEXT PRIMARY KEY,
  owner_id TEXT UNIQUE REFERENCES members(id) ON DELETE CASCADE, -- NULL means shared
  name TEXT,  -- shared lists only
  color TEXT, -- shared lists only
  archived INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE stores (id TEXT PRIMARY KEY, name TEXT NOT NULL, position INTEGER NOT NULL);
CREATE TABLE categories (
  id TEXT PRIMARY KEY,
  store_id TEXT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  position INTEGER NOT NULL
);
CREATE TABLE items (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  name_key TEXT NOT NULL UNIQUE,
  default_store_id TEXT REFERENCES stores(id) ON DELETE SET NULL
);
CREATE TABLE placements (
  item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  store_id TEXT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  category_id TEXT NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  PRIMARY KEY (item_id, store_id)
);
CREATE TABLE entries (
  id TEXT PRIMARY KEY,
  list_id TEXT NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
  item_id TEXT REFERENCES items(id) ON DELETE SET NULL,
  text TEXT NOT NULL,
  quantity TEXT NOT NULL DEFAULT '',
  note TEXT NOT NULL DEFAULT '',
  store_id TEXT REFERENCES stores(id) ON DELETE SET NULL,
  created_at INTEGER NOT NULL,
  bought_at INTEGER
);
CREATE INDEX entries_by_list ON entries(list_id, bought_at);
CREATE TABLE applied_ops (op_id TEXT PRIMARY KEY, applied_at INTEGER NOT NULL);
```

- [ ] **Step 5: Run** `go test ./... && go vet ./... && test -z "$(gofmt -l .)"`. Expected: PASS, no output from gofmt.

- [ ] **Step 6: Licenses**

```bash
curl -fsSL https://www.gnu.org/licenses/agpl-3.0.txt -o server/LICENSE
mkdir -p ios && curl -fsSL https://www.mozilla.org/media/MPL/2.0/index.txt -o ios/LICENSE
head -1 server/LICENSE   # GNU AFFERO GENERAL PUBLIC LICENSE
head -1 ios/LICENSE      # Mozilla Public License Version 2.0
```

Replace the root `LICENSE` with exactly:

```
PocketLarder is licensed per directory:

- server/  GNU Affero General Public License v3.0, see server/LICENSE
- ios/     Mozilla Public License 2.0, see ios/LICENSE

Everything else in this repository is under the GNU Affero General Public
License v3.0, the same as the server.
```

- [ ] **Step 7: Commit:** `git add server ios LICENSE && git commit -m "Add the server module, SQLite schema and per-directory licenses"`

---

### Task 2: Members, invites and device tokens

**Files:**
- Create: `server/internal/larder/ids.go`, `server/internal/larder/members.go`
- Create: `server/internal/larder/gen_confusables.go` and the `server/internal/larder/confusables.go` it generates
- Modify: `server/go.mod`, `server/go.sum` (add `golang.org/x/text` v0.43.0)
- Test: `server/internal/larder/ids_test.go`, `server/internal/larder/members_test.go`

**Interfaces:**
- Consumes: `openDB`, `withTx`, `testDB` (Task 1).
- Produces, in `ids.go`:
  - `func newID() string`: a random UUIDv4, lowercase canonical form (`crypto/rand`, no dependency).
  - `func validID(s string) bool`: true only for the 36-character lowercase canonical form.
  - `func newSecret() (secret string, hash []byte)`: 32 bytes from `crypto/rand` as `base64.RawURLEncoding` (43 characters), with `hash = sha256(secret)`.
  - `func secretMatches(secret string, hash []byte) bool`: compares in constant time.
  - `func splitCode(code string) (id, secret string, ok bool)`: invite codes and device tokens are both `<uuid>.<secret>`.
  - `func cleanText(s string, max int) (string, bool)`: normalises to NFC (`golang.org/x/text/unicode/norm`), then collapses all whitespace runs to single spaces (`strings.Fields`) and trims. It rejects invalid UTF-8, control runes, an empty result, and more than `max` runes. It keeps invisible characters: emoji sequences need U+200D, and Persian needs U+200C.
  - `func cleanName(s string, max int) (string, bool)`: for member and device names. It collapses whitespace, enforces the PRECIS Nickname profile (RFC 8266, `precis.Nickname`), then runs `cleanText` with the same `max`, so the length limit applies after normalisation. Nickname applies NFKC (full-width `Ａｌｅｘ` becomes `Alex`) and rejects zero-width characters (U+200B), bidi overrides (U+202E) and stray joiners (U+200D).
  - `func nameKey(clean string) string`: folds case (`cases.Fold`), then maps each character to its prototype from `confusables` (the UTS #39 skeleton: NFD, prototypes, NFD). A lowercase letter takes its capital's prototype, so `AI`, `Al` and `ai` share a key. Lookalikes collide: `Alex`, `alex`, `Аlex` (Cyrillic А) and `Ａｌｅｘ`. It skips the skeleton's removal of default-ignorable characters, which member names can't contain. Items share this key (Tasks 4-5), so lookalike item names also end on one item.
  - `var confusables map[rune]string` in the generated `confusables.go`. `//go:generate go run gen_confusables.go` in `ids.go` builds it from `https://www.unicode.org/Public/17.0.0/security/confusables.txt`, the Unicode version of `golang.org/x/text`'s tables under Go 1.27. Nothing downloads at run time. Regenerating the table, or upgrading `golang.org/x/text`, changes keys: it needs a migration that recomputes `members.name_key` and `items.name_key` and handles names that newly collide.
  - `const maxName = 100; maxQuantity = 32; maxNote = 200; maxDeviceName = 64`.
- Produces, in `members.go`:
  - `type device struct { ID, MemberID string; IsAdmin bool }`.
  - `var errInvalid, errForbidden, errNotFound, errConflict, errLastAdmin, errBadInvite, errUnauthorized = errors.New(...)`, each with its message equal to its API code: `invalid`, `forbidden`, `not_found`, `conflict`, `last_admin`, `invalid_invite`, `unauthorized`.
  - `func createMember(tx *sql.Tx, name string, admin bool, now time.Time) (string, error)`: creates the member and their personal list. The name goes through `cleanName(name, maxName)`. Returns `errInvalid` for a bad name and `errConflict` for a taken one, including a lookalike of one.
  - `func memberByName(tx *sql.Tx, name string) (string, error)`: cleans with `cleanName` and looks up by `nameKey`, so any lookalike spelling finds the member. Returns `errNotFound` if there is none.
  - `func createInvite(tx *sql.Tx, memberID string, now time.Time) (code string, expires time.Time, err error)`, with `expires = now + 24h`.
  - `func revokeInvites(tx *sql.Tx, memberID string) (int, error)`: deletes the member's unredeemed invites (`used_at IS NULL`) and returns how many it deleted. Used invites stay. Returns `errNotFound` for an unknown member.
  - `func redeemInvite(tx *sql.Tx, code, deviceName string, now time.Time) (token string, d device, err error)`: `deviceName` is cleaned with `cleanName(deviceName, maxDeviceName)`, and an empty name becomes `"Unnamed device"`. A non-empty name that fails returns `errInvalid` and leaves the invite untouched. Unknown, wrong-secret, used and expired invites all return `errBadInvite`. An invite is expired from its `expires_at` second onwards (`now.Unix() >= expires_at`). Marks the invite with `UPDATE … SET used_at = ? WHERE id = ? AND used_at IS NULL` and proceeds only when exactly 1 row changed.
  - `func authenticate(tx *sql.Tx, token string, now time.Time) (device, error)`: returns `errUnauthorized` on any failed check and sets `last_seen_at = now` on success. Database errors pass through unchanged, so an outage never looks like a revoked token.
  - `func deleteDevice(tx *sql.Tx, deviceID string) error` returns `errNotFound` if the device doesn't exist.
  - `func setAdmin(tx *sql.Tx, memberID string, admin bool) error` and `func removeMember(tx *sql.Tx, memberID string) error`: both return `errLastAdmin` when the change would leave no admin, and `errNotFound` for an unknown member.
  - `func inviteURL(publicURL, code string) string` returns `pocketlarder://invite?server=<QueryEscape(publicURL)>&code=<code>`. This one string is both the QR payload and the copyable text code.

- [ ] **Step 1: Write the failing tests**

```go
func TestCleanText(t *testing.T) // table:
// "  Burrito \t spice " -> "Burrito spice", true;  "Äpfel" -> "Äpfel", true
// "" / "   " -> false;  "a\x00b" -> false;  strings.Repeat("x", 101) with max 100 -> false;  "\xff" -> false
// "Äpfel" -> "Äpfel" (NFC); an emoji sequence with U+200D and a Persian word with U+200C pass unchanged

func TestCleanName(t *testing.T) // table:
// "Ａｌｅｘ" -> "Alex"; tabs collapse; U+200B, U+202E or a stray U+200D -> false;  51 × "ﬁ" with max 100 -> false

func TestNameKey(t *testing.T)
// equal keys: Alex/alex, Alex/Аlex (Cyrillic А), Alex/Ａｌｅｘ, AI/Al, Aléx precomposed/decomposed,
//             Ian/ian, Tom/TOM, Helen/Нelen (Cyrillic Н)
// different keys: Alex/Alexa, Sam/Pam, Jo/Joe; a to z all differ except i and l

func TestIDs(t *testing.T) // validID(newID()); !validID("x"); !validID(strings.ToUpper(newID())); two newID() differ

func TestInviteRedeemsOnceAndStoresOnlyHash(t *testing.T)
// createMember "Alex" admin; createInvite; stored invites.secret_hash == sha256(secret part of code)
// redeemInvite ok: d.MemberID == alex, d.IsAdmin; devices.secret_hash == sha256(secret part of token)
// second redeemInvite with the same code -> errBadInvite

func TestInviteExpiry(t *testing.T)
// redeem at now+23h59m -> ok;  a second invite redeemed at now+24h+1s -> errBadInvite

func TestInviteWrongSecret(t *testing.T) // same id, different 43-char secret -> errBadInvite

func TestRevokeInvites(t *testing.T)
// Alex has a used and two pending invites, Sam one pending: revokeInvites(alex) -> 2; a revoked code -> errBadInvite
// the used invite stays; Sam's code still redeems; a second revokeInvites(alex) -> 0; unknown member -> errNotFound

func TestAuthenticate(t *testing.T)
// valid token -> device, last_seen_at == now;  token with altered secret -> errUnauthorized
// "garbage" -> errUnauthorized;  after deleteDevice -> errUnauthorized

func TestRemoveMemberRevokesDevicesAndPersonalList(t *testing.T)
// two admins; Sam has a device and an entry on his personal list; removeMember(sam)
// -> Sam's token fails authenticate; no list with owner_id = sam; no entries left on it

func TestLastAdminGuard(t *testing.T)
// sole admin: setAdmin(false) and removeMember -> errLastAdmin;
// after setAdmin(sam, true): setAdmin(alex, false) -> nil

func TestMemberNamesUniqueIgnoringCase(t *testing.T)
// "Alex" then " alex " -> errConflict; "Аlex" (Cyrillic А) -> errConflict; memberByName("Ａｌｅｘ") -> Alex
```

- [ ] **Step 2: Run** `go test ./...`. Expected: FAIL, undefined symbols.
- [ ] **Step 3: Implement `ids.go` and `members.go`** against the Interfaces above.
- [ ] **Step 4: Run** `go test ./... && go vet ./...`. Expected: PASS.
- [ ] **Step 5: Commit:** `git commit -m "Add members, invites and device tokens"`

---

### Task 3: HTTP API: pairing, sign-out, admin

**Files:**
- Create: `server/internal/larder/http.go`
- Test: `server/internal/larder/http_test.go`
- Create: `server/API.md`

**Interfaces:**
- Consumes: everything Task 2 produces.
- Produces:
  - `type server struct { db *sql.DB; publicURL string; now func() time.Time; log *slog.Logger; redeemLimit *windowLimiter }`
  - `func newServer(db *sql.DB, publicURL string, log *slog.Logger) *server`, with `now = time.Now` and a limit of 10 redemptions per minute.
  - `func (s *server) routes() http.Handler`: a `http.ServeMux` with method patterns, wrapped in a logging middleware that logs only method, `r.Pattern`, status and duration.
  - `func (s *server) authed(adminOnly bool, h func(http.ResponseWriter, *http.Request, device)) http.HandlerFunc`: reads `Authorization: Bearer <token>`. It returns 401 `unauthorized` on failure and 403 `forbidden` when `adminOnly` and the member isn't an admin.
  - `func readJSON(w http.ResponseWriter, r *http.Request, limit int64, v any) bool`: `MaxBytesReader` plus `DisallowUnknownFields`. Writes 413 `too_large` or 400 `invalid` and returns false.
  - `func writeJSON(w http.ResponseWriter, status int, v any)`: sets `Content-Type: application/json` and `Cache-Control: no-store`.
  - `func (s *server) fail(w http.ResponseWriter, err error)`: maps errors to statuses as below. Any other error becomes 500 `internal` and is logged as the error value only.
  - `type windowLimiter struct{ max int; window time.Duration; start time.Time; n int; mu sync.Mutex }` with `func (l *windowLimiter) allow(now time.Time) bool`. `shortcut: one server-wide window, not per client IP, because codes are 256-bit; go per-IP if lockouts annoy`.
  - Tests: `type testEnv struct{ t *testing.T; db *sql.DB; srv *server; h http.Handler; now time.Time; logs *bytes.Buffer }` with `newTestEnv(t)`, `(e *testEnv) call(method, path, token string, body any) *httptest.ResponseRecorder` and `(e *testEnv) member(name string, admin bool) (memberID, token string)` (creates, invites and redeems through HTTP). `publicURL` is `https://lists.example.test`.

Errors are returned as `{"error":"<code>"}`:

| error | status |
|---|---|
| `errInvalid` | 400 `invalid` |
| `errUnauthorized` | 401 `unauthorized` |
| `errBadInvite` | 401 `invalid_invite` |
| `errForbidden` | 403 `forbidden` |
| `errNotFound` | 404 `not_found` |
| `errConflict` | 409 `conflict` |
| `errLastAdmin` | 409 `last_admin` |
| (body over limit) | 413 `too_large` |
| (rate limit) | 429 `rate_limited` |

Endpoints (non-sync bodies are capped at 64 KiB):

| Method and path | Auth | Request | Response |
|---|---|---|---|
| `POST /v1/invites/redeem` | none, rate-limited | `{"code","device_name"}` | 200 `{"token","member_id","device_id"}` |
| `POST /v1/invites` | member | `{}` invites a device for yourself; `{"member_id"}` or `{"new_member_name"}` need an admin | 201 `{"url","expires_at","member_id"}` |
| `POST /v1/invites/revoke` | member | `{}` revokes your own unredeemed invites; `{"member_id"}` needs an admin | 200 `{"revoked":n}` |
| `POST /v1/signout` | member | none | 204, current device deleted |
| `GET /v1/admin/members` | admin | none | 200 `{"members":[{"id","name","is_admin","privacy","pending_invites","devices":[{"id","name","created_at","last_seen_at"}]}]}` |
| `PATCH /v1/admin/members/{id}` | admin | `{"is_admin":bool}` | 204 |
| `DELETE /v1/admin/members/{id}` | admin | none | 204 |
| `DELETE /v1/admin/devices/{id}` | admin | none | 204 |

The redemption rate limit is checked before anything else, so a 429 says nothing about the code. Path IDs that fail `validID` return 404. `POST /v1/invites/revoke` calls `revokeInvites`, which is how an invite sent to the wrong person is invalidated before it is redeemed. `pending_invites` counts the member's unredeemed, unexpired invites (`used_at IS NULL AND expires_at > now`).

- [ ] **Step 1: Write the failing tests**

```go
func TestRedeemThenSignOut(t *testing.T)
// createMember+createInvite in a tx; POST redeem {code, device_name:"Phone"} -> 200 with token
// POST /v1/signout with token -> 204; again -> 401

func TestAuthRequired(t *testing.T)
// every authed route with no header, and with "Bearer x.y" -> 401 {"error":"unauthorized"}

func TestRedeemRateLimited(t *testing.T)
// 10 bogus redeems -> 401 each; 11th -> 429; e.now += time.Minute; next -> 401

func TestInvitePermissions(t *testing.T)
// non-admin {} -> 201, url has prefix "pocketlarder://invite?server=https%3A%2F%2Flists.example.test&code="
// non-admin {"new_member_name":"Sam"} -> 403; non-admin {"member_id":<admin>} -> 403
// admin {"new_member_name":"Sam"} -> 201 and Sam exists, not admin; admin {"new_member_name":"sam"} -> 409

func TestAdminMembers(t *testing.T)
// admin GET -> both members, each with its device name and last_seen_at; non-admin -> 403
// Sam with one pending, one redeemed and one expired invite -> "pending_invites":1

func TestHTTPRevokeInvites(t *testing.T)
// non-admin POST /v1/invites {} then POST /v1/invites/revoke {} -> 200 {"revoked":1}; that code's redeem -> 401 invalid_invite
// non-admin {"member_id":<admin>} -> 403; admin {"member_id":<sam>} -> 200; admin {"member_id":newID()} -> 404

func TestHTTPLastAdminGuard(t *testing.T) // Review Focus 5; Task 2 already has TestLastAdminGuard
// sole admin PATCH self {"is_admin":false} -> 409 last_admin; DELETE self -> 409 last_admin

func TestRevokeDevice(t *testing.T) // admin DELETE /v1/admin/devices/{id} -> 204; that token -> 401

func TestSecretsNeverLogged(t *testing.T)
// redeem, a call with a wrong token, an invite creation; e.logs contains none of:
// the invite code, its secret, the token, the wrong token

func TestBodyLimits(t *testing.T)
// redeem with a 100 KiB body -> 413; redeem with an unknown field -> 400
```

- [ ] **Step 2: Run** `go test ./...`. Expected: FAIL.
- [ ] **Step 3: Implement `http.go`** against the Interfaces and tables above.
- [ ] **Step 4: Run** `go test ./... && go vet ./...`. Expected: PASS.
- [ ] **Step 5: Write `server/API.md`**: base URL and `/v1`, the bearer header, the error format and code table, the invite URL format, and each endpoint above with one JSON request and response example. It is the contract for the iOS and future Android clients, so it describes behavior and never mentions iOS.
- [ ] **Step 6: Commit:** `git commit -m "Add pairing, sign-out and admin endpoints"`

---

### Task 4: Sync, snapshot and entry operations

**Files:**
- Create: `server/internal/larder/ops.go`, `server/internal/larder/snapshot.go`
- Modify: `server/internal/larder/http.go` (route `POST /v1/sync`)
- Test: `server/internal/larder/sync_test.go`
- Modify: `server/API.md` (Sync section)

**Interfaces:**
- Consumes: `device`, the errors, `cleanText`, `nameKey`, `validID`, `withTx`, `server.authed`, `readJSON`, `writeJSON` and `testEnv` from earlier tasks.
- Produces:
  - `type op struct` with JSON snake_case fields: `OpID, Type, ID, ListID, ItemID, StoreID, CategoryID, NewItemID string`; `Text, Quantity, Note, Name, Color, DefaultStoreID *string`; `Archived *bool`; `IDs []string`; `Privacy string`. Absent pointer fields mean "unchanged".
  - `type rejection struct { OpID string `json:"op_id"`; Reason string `json:"reason"` }`.
  - `var opHandlers = map[string]func(tx *sql.Tx, me device, o op, now time.Time) error{}`. Task 5 registers its ops here in an `init`.
  - `func applyBatch(tx *sql.Tx, me device, ops []op, now time.Time) ([]rejection, error)`.
  - `func writableList(tx *sql.Tx, me device, listID string) error`: returns nil for a shared list or your own personal list, nil for another member's `open` list, `errForbidden` for `readonly` or `hidden`, and `errNotFound` if the list doesn't exist.
  - `type snapshot struct` and `func buildSnapshot(tx *sql.Tx, me device) (snapshot, error)`. JSON shape:
    `{"me":{"member_id","device_id","is_admin"}, "members":[{"id","name","is_admin","privacy"}], "lists":[{"id","owner_id"|null,"name"|null,"color"|null,"archived","writable"}], "stores":[{"id","name","position"}], "categories":[{"id","store_id","name","position"}], "items":[{"id","name","default_store_id"|null}], "placements":[{"item_id","store_id","category_id"}], "entries":[{"id","list_id","item_id"|null,"text","quantity","note","store_id"|null,"created_at","bought_at"|null}]}`
  - `const maxOps = 500; maxSyncBody = 1 << 20; boughtPerList = 50`.
  - Tests: `(e *testEnv) sync(token string, ops ...op) ([]rejection, snapshot)` (asserts 200), plus `e.store(name) string` and `e.category(storeID, name) string`, which insert directly with SQL.

`POST /v1/sync` takes `{"ops":[...]}` and returns 200 `{"rejected":[...],"snapshot":{...}}`. More than `maxOps` ops returns 400 `invalid`. A body over `maxSyncBody` returns 413. Every op in a 200 response has been consumed, so the client drops it from its queue whether or not it was rejected.

`applyBatch` handles a batch like this, all in the caller's transaction:
1. `DELETE FROM applied_ops WHERE applied_at < now - 90 days`.
2. For each op: if `!validID(o.OpID)`, reject it as `invalid` and continue. Otherwise run `INSERT OR IGNORE INTO applied_ops`. If no row was inserted, skip the op silently, because an earlier delivery already handled it. An unknown `Type` is rejected as `invalid`.
3. If the handler returns one of the sentinel errors, record a rejection whose reason is that error's code. Any other error aborts the whole batch, and the handler returns 500 so the client retries.

`buildSnapshot` visibility: a member sees every shared list (archived ones too), their own list, and other members' lists unless the owner's privacy is `hidden`. `writable` follows `writableList`. Entries: every open entry on visible lists, plus the newest `boughtPerList` bought entries per visible list (`ROW_NUMBER() OVER (PARTITION BY list_id ORDER BY bought_at DESC, id)`). Ordering: stores and categories by `position`, everything else by `id`.

Ops in this task. Every entry op first checks `writableList` on the entry's list. A missing entry is `not_found`.

| type | fields | effect |
|---|---|---|
| `entry.add` | `id, list_id, item_id?, text?, store_id?, quantity?, note?` | With `item_id` (which must exist): `text` = the item's name, `store_id` = the given store, or else the item's default. Without it: `text` is required and cleaned with `maxName`, the store is NULL, and a `store_id` is `invalid`. An existing `id` is a no-op. |
| `entry.update` | `id, quantity?, note?` | Sets whichever is present. Empty strings clear the field. Neither present is `invalid`. |
| `entry.buy` / `entry.unbuy` | `id` | `bought_at = COALESCE(bought_at, now)` / `bought_at = NULL` |
| `entry.delete` | `id` | Deletes the entry. |
| `entry.place` | `id, store_id, category_id?, new_item_id?` | Files or moves an entry. The category must belong to `store_id` (else `invalid`). For an entry with no item, `category_id` and `new_item_id` are required: the entry links to the item whose `name_key` equals `nameKey(entry.text)`, or a new item `{new_item_id, entry.text, default_store_id: store_id}` is created. Then it sets `entry.store_id`. If `category_id` is given, it upserts the placement `(item, store_id)`. If the item has no default store, it gets `store_id`. |
| `member.set_privacy` | `privacy` | Sets your own privacy. Anything but `open`, `readonly` or `hidden` is `invalid`. |

- [ ] **Step 1: Write the failing tests**

```go
func TestSyncAddsUnfiledEntry(t *testing.T)
// Alex adds {text:"burrito spice"} to his own list -> no rejections;
// snapshot entry has text "burrito spice", item_id nil, store_id nil, bought_at nil

func TestResentBatchDoesNotResurrect(t *testing.T) // Review Focus 1
// batch B = [entry.add X]; sync(B); sync([entry.delete X]); sync(B) again with the same op_ids
// -> X absent from the snapshot

func TestBuyAndUnbuy(t *testing.T)
// buy -> bought_at set; buy again keeps the same bought_at; unbuy -> nil

func TestPrivacyEnforced(t *testing.T) // Review Focus 3
// Alex is an admin: admins get no exception
// Sam sets readonly -> Alex's snapshot shows Sam's list with writable false;
//   Alex's entry.add / entry.buy on Sam's list -> rejected "forbidden", entry unchanged
// Sam sets hidden (Sam has open and bought entries) -> Alex's snapshot has no Sam list and
//   no entry with Sam's list_id; Alex's queued entry.update on Sam's entry -> "forbidden"
// Sam sets open -> the list and entries are back for Alex

func TestFilingLinksToExistingItemIgnoringCase(t *testing.T) // Review Focus 2
// store S, category C; Alex adds unfiled "Milk", entry.place {S, C, new_item_id N1} -> item N1 "Milk", default S
// Sam adds unfiled "  milk ", entry.place {S, C, new_item_id N2} -> entry.item_id == N1; one item total

func TestPlaceRejectsForeignCategory(t *testing.T) // category from store T while placing in S -> "invalid"

func TestBoughtCappedPerList(t *testing.T)
// 55 entries bought at increasing times -> the snapshot holds the newest 50

func TestBadOpDoesNotBlockBatch(t *testing.T)
// [ {op_id:newID(), type:"nope"}, {op_id:"x", type:"entry.add", …}, valid entry.add ]
// -> two "invalid" rejections, the last op applied

func TestSyncLimits(t *testing.T) // 501 ops -> 400; a 2 MiB body -> 413
```

- [ ] **Step 2: Run** `go test ./...`. Expected: FAIL.
- [ ] **Step 3: Implement `ops.go`, `snapshot.go` and the route.**
- [ ] **Step 4: Run** `go test ./... && go vet ./...`. Expected: PASS.
- [ ] **Step 5: Extend `API.md`** with: the sync request and response, the snapshot shape, every op from this table, the rules (ops are idempotent by `op_id`; consumed means drop it; the server applies ops in arrival order and the last one wins; each snapshot replaces the client's whole local copy, which is how a newly hidden list leaves other devices), and the client duty this plan cannot enforce: keep unacknowledged ops and re-apply them on top of every snapshot. Also say that "Not filed yet" means no item, no store, or no placement for (item, store).
- [ ] **Step 6: Commit:** `git commit -m "Add sync with entry operations and server-side privacy"`

---

### Task 5: Lists, stores, categories and catalog operations

**Files:**
- Create: `server/internal/larder/catalog.go` (registers handlers in `opHandlers`)
- Test: `server/internal/larder/catalog_test.go`
- Modify: `server/API.md` (op table)

**Interfaces:**
- Consumes: `op`, `opHandlers`, `writableList`, the errors and the `testEnv` sync helpers from Task 4.
- Produces: the ops below. Every name goes through `cleanText(…, maxName)`. A missing target is `not_found`. Any member may run any of these ops.

| type | fields | effect |
|---|---|---|
| `list.create` | `id, name, color` | Creates a shared list. A color outside `red orange yellow green teal blue purple pink gray` is `invalid`. |
| `list.update` | `id, name?, color?, archived?` | Shared lists only. On a personal list it is `forbidden`. |
| `store.create` | `id, name` | `position = max + 1` |
| `store.rename` | `id, name` | |
| `store.delete` | `id` | Foreign keys cascade and set references to NULL (Task 1). |
| `store.reorder` | `ids` | See the reorder rule below. |
| `category.create` | `id, store_id, name` | `position = max + 1` within the store |
| `category.rename` | `id, name` | |
| `category.delete` | `id` | |
| `category.reorder` | `store_id, ids` | See the reorder rule below. |
| `item.update` | `id, name?, default_store_id?` | A `name_key` held by another item is a `conflict`. A case-only change of the same item is fine. |
| `item.place` | `id, store_id, category_id` | Upserts the placement. The category must be in the store. |
| `item.delete` | `id` | Entries keep `text` and lose `item_id`. |

Reorder rule: the existing IDs listed in `ids` take positions `0..k-1` in the given order. Every other row in scope keeps its relative order after them. Unknown IDs are ignored. This way a stale client can't knock out a store it has never heard of.

- [ ] **Step 1: Write the failing tests**

```go
func TestStoresAndCategories(t *testing.T)
// create A, B -> positions 0, 1; store.reorder [B, A] -> snapshot order B, A
// categories in A: create x, y; rename y; category.reorder {A, [y, x]} -> y, x

func TestReorderKeepsUnlisted(t *testing.T) // stores A, B, C; reorder [C, A] -> C, A, B

func TestDeletingStoreKeepsEntries(t *testing.T) // Review Focus 4
// item filed in store S with an open entry; store.delete S
// -> the entry is still in the snapshot with store_id nil; item.default_store_id nil; no placements

func TestDeletingCategoryKeepsEntries(t *testing.T)
// category.delete -> the entry keeps store_id and item_id; the placement is gone

func TestDeletingItemKeepsEntryText(t *testing.T) // item.delete -> entry.item_id nil, text unchanged

func TestItemRenameConflict(t *testing.T) // Review Focus 2
// items "Milk", "Bread": rename Milk -> "BREAD" rejected "conflict"; rename Milk -> "MILK" applied

func TestSharedLists(t *testing.T)
// list.create {name:"Party", color:"teal"} -> visible to Sam with writable true
// color "chartreuse" -> "invalid"; list.update {archived:true} -> still in the snapshot, archived true
// list.update on Alex's personal list -> "forbidden"
```

- [ ] **Step 2: Run** `go test ./...`. Expected: FAIL.
- [ ] **Step 3: Implement `catalog.go`.**
- [ ] **Step 4: Run** `go test ./... && go vet ./...`. Expected: PASS.
- [ ] **Step 5: Extend `API.md`**'s op table with these ops and the reorder rule.
- [ ] **Step 6: Commit:** `git commit -m "Add list, store, category and catalog operations"`

---

### Task 6: CLI: serve, invite, backup

**Files:**
- Create: `server/main.go`, `server/internal/larder/cli.go`
- Test: `server/internal/larder/cli_test.go`
- Modify: `AGENTS.md` (Dev server section)

**Interfaces:**
- Consumes: `openDB`, `withTx`, `createMember`, `memberByName`, `createInvite`, `revokeInvites`, `inviteURL`, `newServer` and `routes`.
- Produces: `func Run(ctx context.Context, args []string, getenv func(string) string, stdout, stderr io.Writer) int`. Exit codes: 0 for success, 1 for failure, 2 for usage. `main.go` contains only the line `os.Exit(larder.Run(ctx, os.Args[1:], os.Getenv, os.Stdout, os.Stderr))`, with `ctx` from `signal.NotifyContext(…, os.Interrupt, syscall.SIGTERM)`.

Environment:
- `POCKETLARDER_DATA_DIR`: defaults to `/data`. The database is `<dir>/pocketlarder.db`.
- `POCKETLARDER_LISTEN`: defaults to `:8080`.
- `POCKETLARDER_PUBLIC_URL`: required by `serve` and `invite`. It must be `https://host[:port]`, or `http://localhost[:port]` / `http://127.0.0.1[:port]`, with no path, query or fragment. A trailing `/` is stripped.

Data directory (carried forward from Task 1's security review):
- `Run` rejects a `POCKETLARDER_DATA_DIR` containing `?`, `#` or `%`: exit 1, with stderr naming the variable. `openDB` builds its DSN as `"file:"+path+"?..."`, so a `?` in the path silently drops all four pragmas, including `foreign_keys(1)`, and `#` and `%` are read as URI syntax.
- `Run` creates the data directory as 0700 when it doesn't exist, and the database files end up 0600. Under umask 022, SQLite creates the database, `-wal` and `-shm` files as 0644. SQLite gives `-wal` and `-shm` the mode of the database file, so `Run` creates `pocketlarder.db` as 0600 before `openDB`. A scratch test with `modernc.org/sqlite` v1.61.0 confirmed this on 2026-10-27, and `TestCLIFileModes` keeps checking it.

Commands:
- `serve`: runs an `http.Server` with `ReadHeaderTimeout 10s`, `ReadTimeout 30s`, `WriteTimeout 30s` and `IdleTimeout 120s`, and logs JSON to stdout with `slog`. On `ctx.Done()` it calls `Shutdown` with a 10-second limit and returns 0.
- `invite --new-admin <name>` creates an admin. `invite <member name>` makes a device invite for an existing member. Both print `Invite for <name>, valid until <RFC 3339>:` followed by the URL on its own line.
- `invite --revoke <member name>` deletes the member's unredeemed invites with `revokeInvites`, prints `Revoked <n> invite(s) for <name>.` and exits 0. An unknown member exits 1. The CLI needs this because the first admin's invite comes from the CLI.
- `backup <path>` runs `VACUUM INTO ?`. It is safe while `serve` is running.

- [ ] **Step 1: Write the failing tests**

```go
func TestCLIInviteNewAdmin(t *testing.T)
// Run(["invite","--new-admin","Alex"]) with DATA_DIR=t.TempDir(), PUBLIC_URL=https://lists.example.test -> 0
// stdout contains "pocketlarder://invite?server=https%3A%2F%2Flists.example.test&code="; Alex is an admin

func TestCLIInviteExisting(t *testing.T) // "alex" -> 0; "Zed" -> 1, stderr mentions "Zed"

func TestCLIInviteRevoke(t *testing.T)
// after invite --new-admin Alex: invite --revoke alex -> 0, stdout "Revoked 1 invite(s) for alex."
// openDB shows Alex with no unredeemed invites; invite --revoke Zed -> 1

func TestCLIPublicURL(t *testing.T)
// http://lists.example.test -> 1; https://lists.example.test/app -> 1; http://localhost:5100 -> 0

func TestCLIBackup(t *testing.T) // after an invite, backup to tmp/b.db -> 0; openDB(b.db) has Alex

func TestCLIDataDirRejectsURIChars(t *testing.T)
// DATA_DIR=t.TempDir()+"/a?b", "/a#b" and "/a%b", invite --new-admin Alex -> 1 each, stderr mentions "POCKETLARDER_DATA_DIR"

func TestCLIFileModes(t *testing.T)
// DATA_DIR=t.TempDir()+"/data" (doesn't exist yet), invite --new-admin Alex -> 0
// the data dir is 0700; pocketlarder.db and any -wal/-shm files next to it are 0600

func TestServe(t *testing.T)
// grab a free port via net.Listen("127.0.0.1:0") then close it; Run serve in a goroutine
// POST /v1/sync without a token -> 401 (retry for up to 2s while it starts); cancel ctx -> Run returns 0 within 5s

func TestUsage(t *testing.T) // no args and "frobnicate" -> 2
```

- [ ] **Step 2: Run** `go test ./...`. Expected: FAIL.
- [ ] **Step 3: Implement `cli.go` and `main.go`.**
- [ ] **Step 4: Run** `go test ./... && go vet ./... && CGO_ENABLED=0 go build -o /dev/null .`. Expected: PASS, and the static build succeeds.
- [ ] **Step 5: `AGENTS.md` Dev server**: replace the section's body with: `cd server && POCKETLARDER_DATA_DIR=$(mktemp -d) POCKETLARDER_LISTEN=127.0.0.1:<port> POCKETLARDER_PUBLIC_URL=http://localhost:<port> go run . serve`, plus the same environment with `go run . invite --new-admin Dev` to get an invite. Keep the sentence that factory agents start their own server on the port their prompt gives.
- [ ] **Step 6: Commit:** `git commit -m "Add the pocketlarder command: serve, invite, backup"`

---

### Task 7: Container, hosting docs, repo docs

**Files:**
- Create: `server/Dockerfile`, `server/deploy/compose.yaml`, `server/deploy/Caddyfile`, `README.md`

`AGENTS.md` (Setup, Validation) and `factory/checks.sh` were set up before Task 1, and Task 6 documents the dev server.

- [ ] **Step 1: `server/Dockerfile`**

```dockerfile
FROM golang:1.27 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/pocketlarder . && mkdir /out/data

FROM scratch
COPY --from=build /out/pocketlarder /usr/local/bin/pocketlarder
COPY --from=build --chown=65532:65532 --chmod=700 /out/data /data
ENV PATH=/usr/local/bin POCKETLARDER_DATA_DIR=/data POCKETLARDER_LISTEN=:8080
USER 65532:65532
VOLUME /data
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/pocketlarder"]
CMD ["serve"]
```

`--chmod=700` makes `/data` 0700, so a new named volume starts out private to uid 65532. `mkdir -m 700 /out/data` in the build stage is not enough: `COPY` copies the directory's contents, not its mode, and creates `/data` as 0755 (checked with Docker 29.9.2 on 2026-10-27).

- [ ] **Step 2: `server/deploy/compose.yaml`**: the `pocketlarder` service with `build: ..`, `container_name: pocketlarder`, `restart: unless-stopped`, `read_only: true`, `cap_drop: [ALL]`, `security_opt: ["no-new-privileges:true"]`, `POCKETLARDER_PUBLIC_URL: https://lists.example.com`, the named volume `pocketlarder-data:/data`, and `ports: ["127.0.0.1:8080:8080"]`.
- [ ] **Step 3: `server/deploy/Caddyfile`**

```
lists.example.com {
	encode zstd gzip
	reverse_proxy 127.0.0.1:8080
}
```

- [ ] **Step 4: `README.md`**: what PocketLarder is (two sentences from the spec's Intent), self-hosting (`docker compose -f server/deploy/compose.yaml up -d --build`, the Caddy block, `docker exec pocketlarder pocketlarder invite --new-admin <name>`, `docker exec pocketlarder pocketlarder backup /data/backup-$(date +%F).db`, and the note that scheduling backups is the host's job), the license summary, and a link to `server/API.md`.
- [ ] **Step 5: Verify the image** (Docker is installed on the factory machine and the user is in the `docker` group):

```bash
docker compose -f server/deploy/compose.yaml up -d --build
docker exec pocketlarder pocketlarder invite --new-admin Test        # prints an invite URL
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8080/v1/sync   # 401
docker exec pocketlarder pocketlarder backup /data/check.db          # exit 0
docker inspect -f '{{.HostConfig.ReadonlyRootfs}} {{.Config.User}}' pocketlarder   # true 65532:65532
docker run --rm --volumes-from pocketlarder busybox sh -c 'stat -c "%a %u:%g %n" /data /data/pocketlarder.db*'   # 700 for /data, 600 for each db file, all 65532:65532
docker compose -f server/deploy/compose.yaml down -v                 # clean up
```

- [ ] **Step 6: Commit:** `git commit -m "Add the container image, hosting examples and repo docs"`
