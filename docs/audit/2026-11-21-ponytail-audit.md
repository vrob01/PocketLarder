# Code audit, 2026-11-21

Made with the ponytail-audit skill (ponytail 5.3.3) on the branch `audit/ponytail`, from `main` at d7d6e99 (server 1.0.0,
app 1.0.0). The audit itself only reports; this section is the state of its findings since.

Status: findings 1-3 and 5-10 are fixed on this branch. Finding 4 is open as issue #102. A code review of the fixes
found that fix 1 missed an İ with a mark attached (for example U+0130 U+0301); that is fixed too, with a test. Fixes
5-10 save fewer lines than estimated below: about 4 lines of code in all, because the new helpers carry doc comments.

What this repo does: PocketLarder is a shopping list app for one household. A small Go server keeps the lists in one
SQLite database and answers the phones over a JSON API. The iPhone app keeps a copy on the phone, queues every change
while offline, and sends the queue to the server, which answers with the whole household's data.

Load assumed: one household, a few members with a few phones each. Each phone syncs about once a minute while open,
plus once after each change. Expected size: a few hundred items and entries.

## Should fix

1. **The phone and the server disagree on the letter İ** (`ios/PocketLarderKit/Sources/PocketLarderKit/Text.swift:31`,
   `server/internal/larder/ids.go:131`)
   - **What this is:** `nameKey` decides when two item names are "the same item", ignoring case. The server and the app
     each have a copy of this rule.
   - **Problem:** Go lowercases the Turkish capital "İ" (U+0130) to a plain "i". Swift lowercases it to "i" plus a
     combining dot (U+0307). So for the server "İrmik" and "irmik" are one item, and for the phone they are two. If
     someone types "İrmik" and the catalog has "irmik", the phone adds an unfiled entry instead of the item. Filing an
     entry named "İrmik" shows a new item on the phone until the next sync links it to "irmik". Checked: Go gives
     "irmik", Swift gives "i̇rmik". Greek capital sigma behaves the same in both.
   - **Fix:** In Swift's `nameKey`, map U+0130 to "i" before lowercasing:
     `cleanText(s, max: .max)?.replacingOccurrences(of: "\u{130}", with: "i").lowercased() ?? ""`, with a one-line
     comment on why. Add `#expect(nameKey("İrmik") == nameKey("irmik"))` to `TextTests.swift`. The server stays as it
     is, so no stored data changes.
   - **If we skip it:** Users who type a Turkish İ sometimes get an unfiled entry for an item they already have. The
     next sync corrects the view, so no data is lost. That is why this is not under Must fix.

2. **No test checks that the phone predicts the server correctly**
   (`ios/PocketLarderKit/Sources/PocketLarderKit/Apply.swift:158`,
   `ios/PocketLarderKit/Tests/PocketLarderKitTests/ContractTests.swift:49`)
   - **What this is:** `apply` repeats in Swift what each server op does in Go, so the phone shows a change before the
     server confirms it. These are two copies of 20 rules in two languages.
   - **Problem:** Each side has its own tests, and the contract test `everyOpTypeIsAccepted` checks only that the server
     rejects nothing. Nothing fails when the two copies drift apart. Finding 1 is exactly such a drift, and no test
     caught it.
   - **Fix:** Add one contract test. It reads a snapshot, sends a batch of ops that creates and changes things, and
     compares the server's answer with `applying` the same ops to the snapshot from before. It compares only the rows
     whose ids the test made (other contract tests share the server and run in parallel), and it ignores times and
     row order. About 30 lines of test.
   - **If we skip it:** A later change to one side shows wrong data on the phone until the next sync, and only a user
     notices.

3. **The gate stops waiting for the iOS build after 45 minutes, but the build may run 75** (`factory/checks.sh:71`)
   - **What this is:** For branches that touch `ios/`, `checks.sh` waits for the GitHub `ios` run of the commit.
   - **Problem:** It waits at most 2700 seconds (45 minutes). The `ios` job is allowed 75 minutes
     (`.github/workflows/ios.yml:37`), and runs took 51 to 55 minutes in November. If the gate starts while the run is
     still going, it reports "failed or timed out" for a run that passes later. Today the builder waits for the run
     before the gate starts, so this happens only when that wait is cut short.
   - **Fix:** Wait as long as the job may run, plus the time to find the run: `timeout 4800`. One number.
   - **If we skip it:** Now and then a job fails its gate for a slow build, and someone has to see that and run the gate
     again.

4. **Two HTTP handlers are near-copies** (`server/internal/larder/http.go:317-345` and `383-411`)
   - **What this is:** `revoke` (POST /v1/invites/revoke) and `clear` (POST /v1/invites/clear) both read a
     `member_id`, allow it only for admins, recheck the caller, run one database function and answer a count.
   - **Problem:** The 29 lines are the same apart from the function called and the answer's key. The comment on `clear`
     even says it must follow `revoke`'s rule. A later change to who may name a member can land in one and miss the
     other.
   - **Fix:** One handler maker, for example
     `s.memberCount("revoked", func(tx *sql.Tx, id string) (int, error) { return revokeInvites(tx, id) })`, used for
     both routes. About 14 lines fewer.
   - **If we skip it:** Nothing breaks today. Any rule change has to be made twice.

5. **Two copies of "put an item in a category"** (`server/internal/larder/ops.go:244-252, 278-283`,
   `server/internal/larder/catalog.go:251-259`)
   - **What this is:** `entry.place` and `item.place` both check that the category belongs to the store, and both write
     the placement with the same `INSERT ... ON CONFLICT` statement.
   - **Problem:** The same rule and the same SQL sit in two places, and they must change together.
   - **Fix:** One helper, `placeIn(tx, item, store, category)` for the upsert, and one, `categoryInStore(tx, category,
     store)` for the check, both in `catalog.go`. About 8 lines fewer.
   - **If we skip it:** Nothing breaks today. A change to placements has to be made twice.

## Nice to have

6. **`knownMember` repeats `found`** (`server/internal/larder/members.go:104-110`)
   - **What this is:** It answers `errNotFound` when no member has the id.
   - **Problem:** `found(tx, "members", id)` in `catalog.go:45` does the same.
   - **Fix:** Delete `knownMember` and call `found(tx, "members", memberID)` in its three callers. 7 lines fewer.
   - **If we skip it:** Two helpers for one job.

7. **The app sorts stores and categories again** (`ios/PocketLarder/Setup/StoresView.swift:187-194`,
   `ios/PocketLarderKit/Sources/PocketLarderKit/Shelf.swift:55, 113`)
   - **What this is:** `storesInOrder` and `categoriesInOrder` sort by position, then id.
   - **Problem:** The kit has the same sort as the private `byPosition`, and inline in `shelf`. Three copies of one order.
   - **Fix:** Make the two functions public in `Shelf.swift`, use them inside `shelf`, and delete `byPosition` and the
     app's copies. About 6 lines fewer.
   - **If we skip it:** If the order rule ever changes, the setup screens and the main screen can disagree.

8. **Suggestions fold every item name many times per keystroke**
   (`ios/PocketLarderKit/Sources/PocketLarderKit/Adding.swift:8-23`)
   - **What this is:** While typing in the add bar, `suggestions` finds matching items. "Fold" means removing case and
     accents for the comparison.
   - **Problem:** It folds each name in the filter, again in every sort comparison, and twice more for the prefix split.
     With 500 items that is about 10,000 folds per keystroke, where 500 would do. Not measured on a phone.
   - **Fix:** Fold each name once: `let folded = s.items.map { (fold($0.name), $0) }`, then filter, sort and split on
     that.
   - **If we skip it:** Typing may lag once the catalog grows to several hundred items.

9. **Three copies of "sign this token out in the background"** (`ios/PocketLarder/AppModel.swift:243-244, 252-253,
   277-278`)
   - **What this is:** After a sign-in that lost a race, a failed Keychain save, or a forced sign-out, the app tells the
     server once, without waiting.
   - **Problem:** The same two lines, with the same reasoning, three times.
   - **Fix:** One private method, `signOutQuietly(server:token:)`, with the comment once. 3 lines fewer.
   - **If we skip it:** Only some extra reading.

10. **A comment still points at a plan task** (`server/internal/larder/http.go:175-176`)
    - **What this is:** The comment on `recheck`.
    - **Problem:** It says "Task 4's POST /v1/sync reads a body too and needs this." The sync route has existed since
      then, so the sentence only confuses.
    - **Fix:** Delete that sentence.
    - **If we skip it:** A reader looks for a Task 4 that no longer matters.

Verdict: healthy. Nothing must be fixed. Fix 1 first, together with the test in 2, which would have caught it.

Lean: -38 lines, -0 dependencies possible.

Not checked: the app was not built or run (no Xcode here; the GitHub `ios` run builds it). UI layout and copy, the UI and
screenshot tests, `Localizable.xcstrings`, `PRIVACY.md`, `server/API.md` against the code, and `.claude/` and
`factory/` beyond `checks.sh` were not reviewed. No load test was run. The server tests, `go vet` and `gofmt` pass, and
the 88 kit tests pass in Docker; the contract tests were skipped, because they need a running server.
