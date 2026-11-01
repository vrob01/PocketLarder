# PocketLarder iOS App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The PocketLarder iPhone app: invite sign-in, a full offline copy of the household's lists with a queue that never loses or undoes a change, the dense store-ordered list, adding, filing and moving, settings, and the admin area, built by the factory on Linux and checked on GitHub's Mac runners.

**Architecture:** All logic that isn't a screen lives in the Swift package `ios/PocketLarderKit` (models, API client, local op application, the sync engine `Larder`, grouping, search), which builds and tests on Linux in Docker, including contract tests against a real server. The SwiftUI app `ios/PocketLarder` holds only screens and platform glue (Keychain, links, QR codes, share sheet). It builds, tests and renders screenshots on GitHub Actions `xcode-27` runners, and the factory's gate waits for that run.

**Tech Stack:** Swift 6.4 (Xcode 27, language mode 6), SwiftUI, Observation, Swift Testing (package and app unit tests), XCTest (UI tests), Docker image `swift:6.4.2-noble` on Linux, GitHub Actions (`xcode-27` runner, `actions/checkout@v5`, `actions/upload-artifact@v4`). No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-10-30-pocketlarder-ios-design.md` (the app design, which wins where it differs), building on `docs/superpowers/specs/2026-10-27-pocketlarder-design.md` (the product spec) and `server/API.md` (the contract). Mockups: `docs/superpowers/specs/2026-10-30-pocketlarder-ios-mockups/` and `docs/superpowers/specs/2026-10-27-pocketlarder-mockups/`.

**Status:** approved by the owner on 2026-10-31. Execution: Task 0 by hand, in a session with the owner, because it changes protected factory files. Tasks 1–9 go through the software factory, one GitHub issue per task, one at a time and in order, each built on the merged PR of the one before.

This is plan 2 of 3. Plan 3 adds OIDC to the server and the app.

## Global Constraints

- iOS 27.0 or newer, iPhone only (`TARGETED_DEVICE_FAMILY = 1`), portrait and landscape. Swift language mode 6 with complete concurrency checking.
- No third-party code: the package has no dependencies, and the app depends only on `PocketLarderKit` and Apple frameworks. No analytics, no crash reporting, no logging of request or response bodies.
- The contract is `server/API.md`. IDs are lowercase UUIDs. JSON keys are snake_case. Timestamps are RFC 3339 UTC without fractions.
- Every op gets a fresh random (v4) lowercase UUID `op_id` (`newID()`, Task 2) when it is created, and it is never reused. A repeated `op_id` is skipped silently by the server, so reuse loses a change.
- A sync never undoes a local change: unacknowledged ops are re-applied, in queue order, over every snapshot (Task 3).
- The app refuses a server address that isn't `https://`, except `http://localhost[:port]` and `http://127.0.0.1[:port]`.
- The device token lives only in the Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, not synchronizable). Tokens, invite codes and invite URLs never appear in logs, error messages, test output or screenshots.
- Every user-facing string is in `ios/PocketLarder/Localizable.xcstrings`, with English and German (informal "du"). Copy quoted in this plan or the design is exact English.
- Accessibility: Dynamic Type up to the accessibility sizes, VoiceOver labels on every control, tap targets of at least 44×44 points, color never the only signal, Reduce Motion respected.
- Kit tests on Linux, from the repo root (written into `AGENTS.md` in Task 1, called **the kit tests** below):
  `docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD/ios/PocketLarderKit:/pkg" -w /pkg swift:6.4.2-noble swift test`
  The `--user` matters: files Docker writes as root can't be cleaned up without sudo.
- The factory machine can't run Xcode. App code is checked by the `ios` workflow on GitHub. After pushing, wait for the run of your HEAD commit and read its log and screenshots (Task 0 writes the commands into `builder.md`).
- Every task's PR body ends with a `## On your phone` section that copies that task's phone checklist from this plan. The owner runs it after the merge, and anything that's off becomes a new factory issue.
- Every task is on the `ui` surface. Tasks 2, 3, 4, 8 and 9 also touch auth, sync or the API and get the security review.
- The Mac setup guide is never committed (see "Owner's Mac setup guide").

## Decisions this plan makes

The design leaves these to the builder.

- **Layout:** `ios/PocketLarderKit/` (package), `ios/PocketLarder/` (app sources, assets, strings, fixtures), `ios/PocketLarderTests/` (hosted unit tests), `ios/PocketLarderUITests/` (screenshot tests), `ios/Config/` (xcconfig, `Info.plist`), `ios/PocketLarder.xcodeproj`.
- **Xcode project:** written by hand, `objectVersion = 77`, with one `PBXFileSystemSynchronizedRootGroup` per source folder, so a new file never touches `project.pbxproj`. `Info.plist` and the xcconfig sit outside the synchronized folders. The package is an `XCLocalSwiftPackageReference` with `relativePath = PocketLarderKit`.
- **Signing:** `ios/Config/PocketLarder.xcconfig` (committed) sets `PRODUCT_BUNDLE_IDENTIFIER = $(PL_BUNDLE_ID)` with the default `PL_BUNDLE_ID = org.pocketlarder.app`, and ends with `#include? "Local.xcconfig"`. The gitignored `ios/Config/Local.xcconfig` on the Mac sets `DEVELOPMENT_TEAM` and a unique `PL_BUNDLE_ID`. CI builds with `CODE_SIGNING_ALLOWED=NO`.
- **JSON:** Swift property names are the API names in camelCase (`listId`, `defaultStoreId`), and `JSON.encoder` and `JSON.decoder` convert to and from snake_case with ISO 8601 dates. Absent optionals are left out, which keeps the server's unknown-field check happy.
- **Local copy:** `snapshot.json` and `queue.json` in `Application Support/Larder/`. Both are written atomically, and the directory is excluded from backup.
- **Queue entries carry their creation time** (`PendingOp.at`). Applying them locally uses it for `created_at` and `bought_at`, so re-applying over each snapshot gives stable times.
- **Sync timing:** about 1 second after a change (`Larder.syncDelay`), every 60 seconds while the app is active, on becoming active, and on pull-to-refresh.
- **Preferences:** `UserDefaults` keys `layout` (`rows`, `tiles`) and `appearance` (`system`, `light`, `dark`), read with `@AppStorage`. A launch argument such as `-appearance dark` sets them for UI tests.
- **Fixtures:** in Debug builds, the launch argument `-fixture household` signs in to a fake server, `FixtureTransport` (Task 5). It serves `ios/PocketLarder/Fixtures/household.json` and applies the ops it receives with `applying` (Task 3), so screenshot tests can tap through real behavior.
- **Screenshots:** UI tests attach `XCTAttachment(screenshot:)` named `<screen>-<en|de>-<light|dark>[-<rows|tiles>]` with `lifetime = .keepAlways`. The workflow exports them with `xcrun xcresulttool export attachments` and uploads the artifact `screenshots`.
- **Contract tests** run only when `POCKETLARDER_TEST_SERVER` and `POCKETLARDER_TEST_INVITE` are set, which `factory/checks.sh` does (Task 0). The server allows 10 redemptions a minute, so the whole suite redeems at most 8 invites.
- **Tag colors:** one light and one dark color per `ListColor` token in `ios/PocketLarder/ListColor+Color.swift` (Task 5). The accent color is `#0A7D6B` in light mode and `#3FD1B8` in dark mode.

## Review Focus

1. **A change made while a sync request is in flight**, such as crossing something off during the request, must survive the response and stay on screen. Test: Task 3, `opsAddedDuringSyncSurvive`.
2. **The app is killed right after an offline change, before any sync.** On relaunch the change is still shown and still gets sent. Test: Task 3, `queueSurvivesRelaunch`.
3. **More than 500 ops queued during a long offline stretch** go out in queue order, 500 at a time, each request after the previous answer. Test: Task 3, `longQueueSendsInOrderedBatches`.
4. **An invite pasted from a messaging app** comes with surrounding text, line breaks and punctuation stuck to the link. The link is still found, the fields fill and the code stays exact. Test: Task 1, `findsInviteInsideText`.
5. **The list on screen becomes hidden by its owner.** The app returns to My view and says why, instead of showing an empty or stale list. Tests: Task 3, `hiddenListNotice`, and Task 5, `hiddenScopeFallsBackToMyView`.

---

### Task 0: Teach the factory to build iOS (by hand, not a factory issue)

`factory/*`, `.claude/*` and, from this task on, `.github/*` are protected, so Claude makes these changes in a session with the owner, on a branch the owner merges, before Task 1's issue gets the `factory` label.

**Files:**
- Create: `.github/workflows/ios.yml`
- Modify: `factory/config.json`, `factory/checks.sh`, `factory/bin/gate`
- Modify: `.claude/agents/builder.md`, `.claude/agents/reviewer-ui.md`, `.claude/agents/reviewer-ux.md`, `.claude/skills/factory/SKILL.md`
- Modify: `AGENTS.md` (Status)

- [ ] **Step 1: Protect workflows.** Add `".github/*"` to `protected_paths` in `factory/config.json`, and make the gate refuse additions under protected paths too. Task 1 is a branch like any other, so it can't write the workflow that judges it. A builder fighting a red build could otherwise weaken the checks for good.

- [ ] **Step 2: `factory/checks.sh`.** Keep the Go block unchanged. After it, add:

```bash
changed=$(git diff --name-only "origin/main...HEAD")

# Kit and contract tests: any branch touching ios/ or server/, once the package exists.
if [ -f ios/PocketLarderKit/Package.swift ] && grep -qE '^(ios|server)/' <<<"$changed"; then
  tmp=$(mktemp -d); pid=
  trap '[ -n "$pid" ] && kill "$pid" 2>/dev/null; rm -rf "$tmp"' EXIT
  port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
  (cd server && CGO_ENABLED=0 go build -o "$tmp/pocketlarder" .)
  export POCKETLARDER_DATA_DIR="$tmp/data" POCKETLARDER_LISTEN="127.0.0.1:$port" POCKETLARDER_PUBLIC_URL="http://localhost:$port"
  invite=$("$tmp/pocketlarder" invite --new-admin Contract | tail -n 1)
  "$tmp/pocketlarder" serve >"$tmp/server.log" 2>&1 & pid=$!
  for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$port/v1/sync" && break; sleep 0.2; done
  docker run --rm --network host --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -e POCKETLARDER_TEST_SERVER="http://localhost:$port" -e POCKETLARDER_TEST_INVITE="$invite" \
    -v "$PWD/ios/PocketLarderKit:/pkg" -w /pkg swift:6.4.2-noble swift test
fi

# The app: branches touching ios/ need a green `ios` run on GitHub.
if grep -q '^ios/' <<<"$changed" && [ -z "${FACTORY_SKIP_CI:-}" ]; then
  sha=${FACTORY_CI_COMMIT:-$(git rev-parse HEAD)}
  # The commit must be on GitHub, then: find its `ios` run (wait up to 5 min), watch it (up to 45 min).
  # On failure print the tail of `gh run view <id> --log-failed`, and exit 1.
fi
```

Write the CI block's body with `gh api "repos/{owner}/{repo}/actions/runs?head_sha=$sha"`, picking the run whose `path` is `.github/workflows/ios.yml`, and `timeout 2700 gh run watch "$id" --exit-status --interval 30`. Picking by path means a branch can't answer with a workflow of its own. After the wait, require that the `ios` job's conclusion is `success`, because a skipped job leaves the run green too. A commit that isn't on GitHub fails at once with a message to push the branch, and so does one whose `ios.yml` differs from `origin/main`'s, or a `main` that has none.

Every `git diff` that decides something about paths, here and in the gate, uses `--no-renames -z`. Otherwise a file with a non-ASCII name is quoted and misses `^ios/`, and a rename out of `ios/` lists only its new path.

- [ ] **Step 3: `factory/bin/gate`.**
  - `hook()` runs `checks.sh` with `FACTORY_SKIP_CI=1`, because a stop hook can't wait for a macOS run.
  - `gate(job, merge=True)` reads `COMMIT` from the round's `checks.md`. If the branch touches `ios/` and `git diff --name-only <COMMIT> HEAD` lists any `ios/` path, the merge brought in app changes that GitHub never built: FAIL with "main changed ios/ since the gate: merge origin/main, push, and gate again". Otherwise it runs `checks.sh` with `FACTORY_CI_COMMIT=<COMMIT>`, whose run already passed.

- [ ] **Step 4: `.github/workflows/ios.yml`.**
  - The workflow's `name` is `ios`. It runs on `push` to any branch and on `workflow_dispatch`, with `permissions: contents: read`, `concurrency` per ref with `cancel-in-progress`, and `persist-credentials: false` on checkouts.
  - **Job `changes`** (`ubuntu-latest`): checkout with `fetch-depth: 0`. Its output `ios` is whether `git diff --name-only --no-renames -z origin/main...HEAD` touches `ios/`.
  - **Job `ios`** runs `needs: changes` with `if: needs.changes.outputs.ios == 'true'` on `runs-on: xcode-27` with `timeout-minutes: 45`. It:
    - runs `swift test --package-path ios/PocketLarderKit`;
    - picks the newest available iPhone simulator on the newest iOS runtime (`xcrun simctl list devices available -j`);
    - runs `xcodebuild test -project ios/PocketLarder.xcodeproj -scheme PocketLarder -destination "id=$SIM" -resultBundlePath "$RUNNER_TEMP/Tests.xcresult" CODE_SIGNING_ALLOWED=NO`;
    - exports attachments to a folder and uploads the artifact `screenshots`, with `if: always()`;
    - uploads the result bundle as `xcresult` on failure.

- [ ] **Step 5: Agents and skill.**
  - `builder.md`: give the Stop hook `timeout: 900`. Add an "iOS" section:
    - Xcode isn't available here. Run the kit tests (the command from `AGENTS.md`).
    - Run the local checks with `FACTORY_SKIP_CI=1`.
    - After every push touching `ios/`, find the run with `gh run list --commit "$(git rev-parse HEAD)" --json databaseId,workflowName`, wait with `timeout 540 gh run watch <id> --exit-status` (repeating while it exits 124), read failures with `gh run view <id> --log-failed`, and look at `gh run download <id> -n screenshots -D <tmp>` before writing build.md.
    - Copy the plan task's phone checklist into the PR body as `## On your phone`.
  - `reviewer-ui.md` and `reviewer-ux.md`: for a branch touching `ios/`, skip the dev server and `agent-browser`. Download the gated commit's `screenshots` artifact and read the PNGs, at least every screen the task names.
  - `SKILL.md`: run `factory/bin/gate <job>` and `factory/bin/job merge <job>` with `run_in_background: true`, and act on the result when they finish. The skill stays free of repo specifics, so this holds for every job.

- [ ] **Step 6: `AGENTS.md` Status.** Add the iOS design and this plan to the list of documents to read, for `ios/` as well as `server/`.

- [ ] **Step 7: Verify.** On main, `bash factory/checks.sh` passes with the same output and about the same time as before, because no package exists yet. `factory/bin/gate --hook` behavior is unchanged for server jobs. Task 1's first gate is the first test of the iOS paths against the real app. If it shows a bug in this task, fix it by hand the same way.

- [ ] **Step 8: Commit** on `factory/ios-support`: `git commit -m "Teach the factory to gate iOS changes on the GitHub ios run"`. Open a PR. The owner merges it.

---

### Task 1: Xcode project, CI and the signed-out screens

**Files:**
- Create: `ios/PocketLarderKit/Package.swift`, `ios/PocketLarderKit/Sources/PocketLarderKit/Invite.swift`
- Test: `ios/PocketLarderKit/Tests/PocketLarderKitTests/InviteTests.swift`
- Create: `ios/PocketLarder.xcodeproj/project.pbxproj`, `ios/PocketLarder.xcodeproj/xcshareddata/xcschemes/PocketLarder.xcscheme`
- Create: `ios/Config/PocketLarder.xcconfig`, `ios/Config/Local.xcconfig.example`, `ios/Config/Info.plist`
- Create: `ios/PocketLarder/PocketLarderApp.swift`, `ios/PocketLarder/AppModel.swift`, `ios/PocketLarder/Welcome/WelcomeView.swift`, `ios/PocketLarder/Welcome/EnterInviteView.swift`, `ios/PocketLarder/Localizable.xcstrings`, `ios/PocketLarder/Assets.xcassets/` (`AppIcon`, `AccentColor`, `Logo`)
- Test: `ios/PocketLarderTests/AppModelTests.swift`, `ios/PocketLarderUITests/ScreenshotTests.swift`
- Modify: `.gitignore`, `AGENTS.md`, `README.md`

The `ios` workflow already exists (Task 0) and expects these names: project `ios/PocketLarder.xcodeproj`, scheme `PocketLarder`, package `ios/PocketLarderKit`. It's protected: if it has to change, write BLOCKED and say how.

**Interfaces:**
- Produces (package): `Package.swift` with `// swift-tools-version: 6.2`, `platforms: [.iOS("27.0"), .macOS("26.0")]`, library `PocketLarderKit`, test target `PocketLarderKitTests`, and no dependencies.
- Produces, in `Invite.swift`:
  - `public struct Invite: Equatable, Sendable { public let server: URL; public let code: String }`
  - `public func parseInvite(_ text: String) -> Invite?`: finds the first `pocketlarder://invite?…` token in `text`, which may be surrounded by other text or whitespace. It requires host `invite`, a `server` that `normalizeServer` accepts, and a non-empty `code` with no whitespace. Before parsing the token, it drops characters from the token's end until it ends in an ASCII letter, an ASCII digit, `-` or `_`, which is how `server/API.md` says a code ends, so punctuation stuck to a pasted link never reaches the code. A trailing `_` stays, because it's a legal code character. Apart from that, the code is opaque and isn't parsed further.
  - `public func normalizeServer(_ text: String) -> URL?`: trims the text and puts `https://` in front when there's no `://`. It requires scheme `https`, or `http` with host `localhost` or `127.0.0.1`, and a non-empty host. It refuses user info, a path other than `/`, a query and a fragment. It returns `scheme://host[:port]` with scheme and host lowercased and no trailing `/`.
- Produces (app):
  - `@MainActor @Observable final class AppModel` with `var pendingInvite: Invite?`, `func open(_ url: URL)` (an invite link sets `pendingInvite`) and `func signIn(_ invite: Invite, deviceName: String) async`. It's empty here. Task 4 implements it and gives it its final return type.
  - `PocketLarderApp` routes to `WelcomeView`. `.onOpenURL` calls `open`. The root applies `@AppStorage("appearance")` with `.preferredColorScheme`.
  - The screenshot naming convention.

- [ ] **Step 1: Write the failing kit tests** in `InviteTests.swift`

```swift
let example = "pocketlarder://invite?server=https%3A%2F%2Flists.example.com&code=fdd4efb3-cf5b-44e7-bec4-94df8e478f5f.ArBLMeKiOpJu5jbcasIRDr8-zlqlbdWCoIfZ9EsLPio"

@Test func parsesInviteURL()
// parseInvite(example) == Invite(server: https://lists.example.com, code: "fdd4efb3-…LPio")

@Test func findsInviteInsideText() // Review Focus 4
// parseInvite("Here's your invite:\n\n" + example + "\nSee you!") == the same Invite; "  " + example + "\n" too
// and with punctuation stuck on: example + ".", example + ")", "(" + example + ")", "[invite](" + example + ")"

@Test func rejectsBadInvites()
// nil for: "https://lists.example.com", "pocketlarder://other?server=…&code=x", the example without &code,
// "…&code=" (empty), "…&code=..." (empty once stripped), and a server of http%3A%2F%2Flists.example.com

@Test(arguments: [
  ("lists.example.com", "https://lists.example.com"), ("HTTPS://Lists.Example.com/", "https://lists.example.com"),
  ("https://lists.example.com:8443", "https://lists.example.com:8443"), (" http://localhost:5100 ", "http://localhost:5100"),
  ("http://127.0.0.1:5100", "http://127.0.0.1:5100"), ("http://lists.example.com", nil), ("https://lists.example.com/app", nil),
  ("https://lists.example.com?x=1", nil), ("https://lists.example.com#x", nil), ("https://u:p@lists.example.com", nil),
  ("ftp://lists.example.com", nil), ("", nil)])
func normalizesServer(input: String, expected: String?)
```

- [ ] **Step 2: Run the kit tests.** Expected: FAIL, `cannot find 'parseInvite' in scope`.
- [ ] **Step 3: Implement `Invite.swift`** against the Interfaces. Use `URLComponents` for parsing. Find the token by splitting on whitespace, and strip its trailing punctuation before `URLComponents` parses it.
- [ ] **Step 4: Run the kit tests.** Expected: PASS.

- [ ] **Step 5: The Xcode project.** Write the following:
  - `project.pbxproj` with three targets:
    - `PocketLarder`, an application, linked to the `PocketLarderKit` product.
    - `PocketLarderTests`, a unit-test bundle hosted by the app, using Swift Testing.
    - `PocketLarderUITests`, a UI-testing bundle targeting the app.
  - Each target's folder is a synchronized root group.
  - Both configurations take `baseConfigurationReference` = `Config/PocketLarder.xcconfig`.
  - The xcconfig sets: `IPHONEOS_DEPLOYMENT_TARGET = 27.0`, `TARGETED_DEVICE_FAMILY = 1`, `SWIFT_VERSION = 6.0`, `GENERATE_INFOPLIST_FILE = YES`, `INFOPLIST_FILE = Config/Info.plist`, `INFOPLIST_KEY_CFBundleDisplayName = PocketLarder`, `INFOPLIST_KEY_UILaunchScreen_Generation = YES`, `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`, `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor`, `LOCALIZATION_PREFERS_STRING_CATALOGS = YES`, `SWIFT_EMIT_LOC_STRINGS = YES`, `CODE_SIGN_STYLE = Automatic`, and the bundle ID rule from Decisions.
  - `knownRegions = (en, de, Base)` and `developmentRegion = en`.
  - `Info.plist` holds only `CFBundleURLTypes` with the scheme `pocketlarder`.
  - The shared scheme `PocketLarder` builds the app and tests both test bundles.
  - `Local.xcconfig.example` shows the two settings, with comments.

- [ ] **Step 6: Assets.**
  - `Logo.imageset` holds the design's `logo.svg` (any) and `logo-dark.svg` (dark), with "Preserve Vector Data".
  - `AppIcon` is a single-size 1024 icon with light, dark and tinted PNGs, rendered from those SVGs:
    ```bash
    docker run --rm -v "$PWD:/w" alpine:3.20 sh -c "apk add --no-cache rsvg-convert && rsvg-convert -w 1024 …"
    ```
    The tinted icon is the light one in grayscale.
  - `AccentColor` uses the colors from Decisions.

- [ ] **Step 7: The screens.**
  - **`WelcomeView`** follows the design's "Welcome screen" and `welcome.html` cards 1–2. The copy is exact:
    - "Shopping lists for your household. To start, this iPhone needs an invite from someone in your household: scan its QR code with the Camera app."
    - The "Enter invite" button.
    - "Set up your own server", which opens `https://github.com/vrob01/PocketLarder#self-hosting`.
    - The footer "Open source and private. No tracking, no ads, no analytics. Your lists are stored only on your household's own server."
  - **`EnterInviteView`** follows the design's "Enter invite" and `enter-invite.html`:
    - Server (with an `https://` prefix label), Invite code (monospace, one line) and Device name (starts as "iPhone", with the design's hint).
    - A `PasteButton` in the top bar, and any field that receives a whole invite link, both fill all three fields with `parseInvite`.
    - Sign in is enabled only when `normalizeServer` accepts the server and the code isn't empty. It calls `AppModel.signIn`.
    - `pendingInvite` prefills the form.
  - All strings go into the catalog in English and German.

- [ ] **Step 8: Write the app tests**

```swift
// PocketLarderTests/AppModelTests.swift
@Test @MainActor func openingInviteLinkSetsPendingInvite()
// model.open(URL(string: example)!) → pendingInvite == parseInvite(example); open(https://example.com) → unchanged

// PocketLarderUITests/ScreenshotTests.swift: for each language (en, de) × appearance (light, dark),
// launched with -AppleLanguages (<lang>) -AppleLocale <lang> -appearance <appearance>:
func testWelcome()              // attaches welcome-<lang>-<appearance>
func testEnterInvite()          // empty form: enter-invite-<lang>-<appearance>; then typing the example link into
                                // Invite code fills Server "lists.example.com", and attaches enter-invite-filled-<lang>-<appearance>
```

- [ ] **Step 9: Docs.**
  - `.gitignore` gets: `ios/Config/Local.xcconfig`, `ios/PocketLarderKit/.build/`, `xcuserdata/`, `DerivedData/`.
  - `AGENTS.md` gets an iOS part under Setup and Validation:
    - the layout;
    - the kit tests command;
    - "Xcode builds run only on GitHub: push, then wait for the `ios` run of your commit";
    - where the screenshots are.
  - `README.md` gets a section "The iOS app" covering:
    - what it needs (a PocketLarder server, an iPhone with iOS 27, a Mac with Xcode 27 to install it);
    - building it: copy `Local.xcconfig.example` to `Local.xcconfig`, set your team and a bundle ID of your own, open `ios/PocketLarder.xcodeproj`, run it on the iPhone;
    - that a free Apple ID needs a reinstall every 7 days;
    - "To use PocketLarder in another language than your iPhone's, open Settings > Apps > PocketLarder > Language."

- [ ] **Step 10: Commit and push.** `git add ios .gitignore AGENTS.md README.md && git commit -m "Add the iOS project, CI and the signed-out screens" && git push`. Wait for the `ios` run of HEAD. Expected: green, with 12 screenshots in `screenshots` (welcome and enter-invite in both languages and appearances, plus the filled form). Look at every screenshot. Fix and push until it's green and they match the mockups.

**On your phone:**
- Install from the Mac. The icon shows on the home screen, and also in dark and tinted mode.
- The welcome screen shows the logo, the text and the footer. "Set up your own server" opens the README in Safari.
- Paste an invite link from `pocketlarder invite <name>` into "Enter invite". All three fields fill. A bare `lists.example.com` gets `https://`, and `http://lists.example.com` keeps Sign in disabled. Signing in isn't in this version yet.
- Put the invite link in a note and tap it. The app opens with the form filled.
- Set the app's language to German (Settings > Apps > PocketLarder > Language). Every text is German, and nothing is cut off.

---

### Task 2: Models and the API client

**Files:**
- Create: `ios/PocketLarderKit/Sources/PocketLarderKit/Model.swift`, `Op.swift`, `API.swift`
- Test: `ios/PocketLarderKit/Tests/PocketLarderKitTests/ModelTests.swift`, `APIClientTests.swift`, `ContractTests.swift`, `Support/FakeTransport.swift`, `Support/Contract.swift`

**Interfaces:**
- Produces, in `Model.swift` (all `public`, `Codable, Equatable, Sendable`, and `Hashable` where SwiftUI needs it):
  - `enum Privacy: String { case open, readonly, hidden }`
  - `enum ListColor: String, CaseIterable { case red, orange, yellow, green, teal, blue, purple, pink, gray }`
  - `struct Snapshot { var me: Me; var members: [Member]; var lists: [ListInfo]; var stores: [Store]; var categories: [Category]; var items: [Item]; var placements: [Placement]; var entries: [Entry] }`
  - `struct Me { var memberId, deviceId: String; var isAdmin: Bool }`
  - `struct Member { var id, name: String; var isAdmin: Bool; var privacy: Privacy }`
  - `struct ListInfo { var id: String; var ownerId: String?; var name: String?; var color: ListColor?; var archived, writable: Bool }`
  - `struct Store { var id, name: String; var position: Int }` and `struct Category { var id, storeId, name: String; var position: Int }`
  - `struct Item { var id, name: String; var defaultStoreId: String? }` and `struct Placement { var itemId, storeId, categoryId: String }`
  - `struct Entry { var id, listId: String; var itemId: String?; var text, quantity, note: String; var storeId: String?; var createdAt: Date; var boughtAt: Date? }`
  - Lookups on `Snapshot`: `func member(_ id: String?) -> Member?`, `list(_:)`, `store(_:)`, `category(_:)`, `item(_:)`, `func placement(item: String?, store: String?) -> Placement?`, and `var myList: ListInfo?` (the list whose `ownerId == me.memberId`).
  - `func newID() -> String`: `UUID().uuidString.lowercased()`.
  - `enum JSON { static let encoder: JSONEncoder; static let decoder: JSONDecoder }`: snake_case keys, `.iso8601` dates, `.sortedKeys` for stable output.
- Produces, in `Op.swift`:
  - `enum OpType: String, Codable, Sendable` with all 20 types under their API names: `entryAdd = "entry.add"`, `entryUpdate`, `entryBuy`, `entryUnbuy`, `entryDelete`, `entryPlace`, `memberSetPrivacy = "member.set_privacy"`, `listCreate`, `listUpdate`, `storeCreate`, `storeRename`, `storeDelete`, `storeReorder`, `categoryCreate`, `categoryRename`, `categoryDelete`, `categoryReorder`, `itemUpdate`, `itemPlace`, `itemDelete`.
  - `struct Op: Codable, Equatable, Sendable` with `let opId: String` and `let type: OpType`, plus optional `id, listId, itemId, storeId, categoryId, newItemId, text, quantity, note, name, defaultStoreId: String?`, `color: ListColor?`, `archived: Bool?`, `ids: [String]?` and `privacy: Privacy?`.
  - `init(_ type: OpType, id: String? = nil, …every field… = nil)`, which sets `opId = newID()`. Encoding leaves out nil fields.
- Produces, in `API.swift`:
  - `protocol Transport: Sendable { func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) }`
  - `struct URLSessionTransport: Transport`: an ephemeral `URLSession`, `dataTask` wrapped in a checked continuation so it also works on Linux (`import FoundationNetworking` when available), a 30-second timeout, and a session-level `URLSessionTaskDelegate` that refuses every redirect with `completionHandler(nil)`, so the bearer token never follows one (the owner's decision on PR #41). `send` returns the 3xx as an ordinary response, and the mapping below turns it into an error. Don't use a per-task delegate: on Linux, `session.data(for:delegate:)` never asks it and follows the redirect with the token. `redirectsAreNotFollowed` in `APIClientTests.swift` covers this.
  - `enum APIError: Error, Equatable, Sendable { case offline; case server(code: String); case unexpected(status: Int) }`
  - Response types, all `Decodable, Equatable, Sendable`:
    - `Redemption { token, memberId, deviceId }`
    - `Rejection { opId, reason }` (also `Encodable`)
    - `SyncResponse { rejected: [Rejection]; snapshot: Snapshot }`
    - `CreatedInvite { url: String; expiresAt: Date; memberId: String }`
    - `AdminMember { id, name: String; isAdmin: Bool; privacy: Privacy; pendingInvites: Int; devices: [AdminDevice] }`
    - `AdminDevice { id, name: String; createdAt, lastSeenAt: Date }`
  - `struct APIClient: Sendable` with `init(server: URL, token: String?, transport: any Transport = URLSessionTransport())` and these methods, all `async throws(APIError)`:
    - `redeem(code: String, deviceName: String) -> Redemption`
    - `sync(_ ops: [Op]) -> SyncResponse`
    - `createInvite(memberId: String? = nil, newMemberName: String? = nil) -> CreatedInvite`
    - `revokeInvites(memberId: String? = nil) -> Int`
    - `signOut()`
    - `members() -> [AdminMember]`
    - `setAdmin(_ memberId: String, _ isAdmin: Bool)`
    - `removeMember(_ memberId: String)`
    - `removeDevice(_ deviceId: String)`
  - Mapping:
    - A transport throw becomes `.offline`.
    - A JSON `{"error": code}` body becomes `.server(code:)`.
    - Any other non-2xx becomes `.unexpected(status:)`.
    - Every request but `redeem` sends `Authorization: Bearer <token>`.
    - Requests with a body send `Content-Type: application/json`. `signOut` sends no body.
- Produces (tests): `FakeTransport`, an actor-backed `Transport` that records requests and answers from a script of `(status, json)` or thrown errors. Also `enum Contract { static var isConfigured: Bool; static func admin() async throws -> APIClient; static func newMember(_ prefix: String) async throws -> (client: APIClient, memberId: String, name: String) }`. `admin()` redeems `POCKETLARDER_TEST_INVITE` once per process, memoized in an actor. `newMember` creates an invite with a unique name such as `"Sam 3f2a"` and redeems it.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func decodesAPIExampleSnapshot()
// the snapshot object of API.md's POST /v1/sync example (copied verbatim into the test) decodes:
// 2 members; lists[0].ownerId == nil, name "Party", color .teal; lists[1].name == nil;
// entries[0].boughtAt == 2026-10-27T09:12:40Z; entries[1].itemId == nil, storeId == nil, quantity "2"

@Test func encodesOnlyGivenFields()
// Op(.entryBuy, id: x) as JSON object has exactly the keys op_id, type, id, with type "entry.buy";
// Op(.itemUpdate, id: x, defaultStoreId: "") keeps "default_store_id": ""

@Test func opIdsAreFreshLowercaseUUIDs()
// 1000 Ops: 1000 distinct opIds, each matching ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$

@Test func requestShapes()
// server https://lists.example.test: redeem → POST /v1/invites/redeem, no Authorization, body {"code","device_name"};
// sync([]) → POST /v1/sync, "Authorization: Bearer t", body {"ops":[]}; signOut → POST /v1/signout, no body;
// setAdmin → PATCH /v1/admin/members/<id> {"is_admin":true}; removeDevice → DELETE /v1/admin/devices/<id>

@Test func errorsMapToCodes()
// 401 {"error":"unauthorized"} → .server(code: "unauthorized"); 429 → "rate_limited"; 500 → "internal";
// 404 text/plain → .unexpected(status: 404); transport throws URLError(.notConnectedToInternet) → .offline

@Test(.enabled(if: Contract.isConfigured)) func redeemAndSnapshot()
// admin: sync([]) → me.isAdmin, myList != nil with writable true, the member "Contract" in members

@Test(.enabled(if: Contract.isConfigured)) func badTokenIsUnauthorized() // token "x.y" → sync throws .server(code: "unauthorized")

@Test(.enabled(if: Contract.isConfigured)) func everyOpTypeIsAccepted()
// one batch with each of the 20 types in a valid order (list.create, store.create ×2, category.create, entry.add unfiled,
// entry.add with item later, entry.place with newItemId, entry.update, entry.buy, entry.unbuy, item.update, item.place,
// store.rename, category.rename, store.reorder, category.reorder, list.update, member.set_privacy open,
// then entry.delete, item.delete, category.delete, store.delete) → rejected == []

@Test(.enabled(if: Contract.isConfigured)) func newMemberFlow()
// admin createInvite(newMemberName:) → parseInvite(url) != nil; redeem it → that client's snapshot.me.isAdmin == false;
// admin members() contains both, each with 1 device
```

- [ ] **Step 2: Run the kit tests.** Expected: FAIL, undefined types.
- [ ] **Step 3: Implement `Model.swift`, `Op.swift` and `API.swift`** against the Interfaces.
- [ ] **Step 4: Run the kit tests, then `bash factory/checks.sh`**, which runs the contract tests against a real server. Expected: PASS. Check that the contract tests ran rather than being skipped.
- [ ] **Step 5: Commit and push.** `git commit -m "Add the app's models and API client with contract tests"`. Wait for the `ios` run. It must be green, with screenshots unchanged.

**On your phone:** nothing new to see. Install it to make sure it still starts.

---

### Task 3: The offline engine

**Files:**
- Create: `ios/PocketLarderKit/Sources/PocketLarderKit/Text.swift`, `Apply.swift`, `LocalFiles.swift`, `Larder.swift`, `Notices.swift`
- Test: `TextTests.swift`, `ApplyTests.swift`, `LarderTests.swift`, `NoticesTests.swift`, `Support/TestData.swift`; modify `ContractTests.swift`

**Interfaces:**
- Consumes: everything Task 2 produces.
- Produces, in `Text.swift`:
  - `enum Limit { static let name = 100, quantity = 32, note = 200 }`
  - `func cleanText(_ s: String, max: Int) -> String?`: the server's `cleanText`. It applies NFC (`precomposedStringWithCanonicalMapping`), collapses whitespace runs to one space and trims. It returns nil for a control character, an empty result, or more than `max` Unicode scalars.
  - `func nameKey(_ s: String) -> String`: the cleaned text, without a limit, lowercased. It returns `""` when nothing is left.
  - `func fold(_ s: String) -> String`: `s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)`, for search and sorting.
- Produces, in `Apply.swift`:
  - `struct PendingOp: Codable, Equatable, Sendable { let op: Op; let at: Date }`
  - `func apply(_ p: PendingOp, to s: inout Snapshot)`
  - `func applying(_ pending: [PendingOp], to s: Snapshot) -> Snapshot`
  - Each op does locally what `API.md` says the server does. **An op the server would reject changes nothing.** Only the rules the API leaves implicit are listed here:
    - Entry ops check `writable` on the entry's list.
    - `entry.add` with `itemId`: text is the item's name, and the store is `storeId`, or else the item's default. Without one: `cleanText(text, max: Limit.name)`, no store. `createdAt = at`.
    - `entry.buy` keeps an existing `boughtAt`, or else sets `at`.
    - `entry.place` on an unfiled entry links to the item with an equal `nameKey`, or else creates `Item(newItemId, text, defaultStoreId: storeId)`.
    - `store.delete`, `category.delete` and `item.delete` cascade as `API.md` describes, and never remove an entry.
    - Reorders follow the API's rule: listed ids first, the rest keep their order, and unknown ids are ignored.
    - `item.update` with a name another item has (`nameKey`) changes nothing.
    - `store.create` and `category.create` take position max + 1, or 0.
    - `list.create` makes a shared list with `writable: true, archived: false`.
    - `member.set_privacy` sets the caller's own member.
- Produces, in `LocalFiles.swift`: `struct LocalFiles: Sendable` with
  - `init(directory: URL)`
  - `func load() -> (snapshot: Snapshot?, queue: [PendingOp])`: an unreadable file counts as missing.
  - `func save(snapshot: Snapshot) throws` and `func save(queue: [PendingOp]) throws`: `Data.write(options: .atomic)` into `snapshot.json` and `queue.json`.
  - `func wipe()`
- Produces, in `Notices.swift`:
  - `enum Notice: Equatable, Sendable { case listHidden(ownerName: String, lostChanges: Bool); case listReadOnly(ownerName: String); case renameConflict(from: String, to: String) }`
  - `func notices(before: Snapshot?, after: Snapshot, sent: [Op], rejected: [Rejection]) -> [Notice]`. `before` is the view the user saw, so an op's list is found through `op.listId`, or through the entry with `op.id` in `before`. The rules:
    - **`listHidden`:** a personal list of another member that is in `before` but not in `after`, while its owner is in `after.members` with privacy `hidden`. `lostChanges` is true when a `forbidden` rejection targets it.
    - **`listReadOnly`:** a `forbidden` rejection on a list that is in `after` with `writable == false`.
    - **`renameConflict`:** a `conflict` rejection of an `item.update` with a name, where `from` is the item's name in `after`, or in `before` when `after` no longer has the item. `before` already shows the refused rename, so it can't come first.
    - There is at most one notice per list. `not_found` rejections produce nothing.
- Produces, in `Larder.swift`: `@MainActor @Observable public final class Larder` with
  - `private(set) var snapshot: Snapshot?`, `pending: [PendingOp]`, `view: Snapshot?` (snapshot with pending applied), `isOffline: Bool` and `notices: [Notice]`
  - `var syncDelay: Duration = .seconds(1)` and `var onSignedOut: ((_ lostChanges: Int) -> Void)?`
  - `init(files: LocalFiles, client: APIClient?)`: loads the files. A nil client never syncs.
  - `func perform(_ ops: [Op], now: Date = .now) throws`: appends, saves the queue (and throws without applying anything if that fails), recomputes `view`, and schedules `sync()` after `syncDelay`, replacing any earlier schedule.
  - `func sync() async`: one request at a time. A call during a request makes the loop run once more.
    - Each round sends `pending.prefix(500)` (and `[]` when nothing is pending, which fetches a snapshot).
    - On 200 it removes exactly the sent `opId`s from `pending`, saves the queue and the snapshot, appends `notices(before: oldView, …)`, recomputes `view`, clears `isOffline`, and loops while ops are pending.
    - On `.server(code: "unauthorized")` it calls `files.wipe()`, clears the state, and calls `onSignedOut(pending.count)` with the count from before the clearing. `APIClient` only produces this code for an HTTP 401.
    - On any other error it keeps `pending` unchanged, sets `isOffline` for `.offline`, for `.server(code: "missing_token")` and for 5xx, and stops.
  - `func dismissNotice()`: removes the first notice.
- Produces (tests): `TestData.household`, a `Snapshot` built in code with fixed lowercase UUIDs. The builder names the id constants. Its contents:
  - **Members:** me is Alex, an admin with privacy open. Sam is a member with privacy open.
  - **Lists:** Alex's personal list, Sam's personal list, shared "Shared" (teal), shared "BBQ Sat" (orange), and shared "Old party" (gray, archived).
  - **Stores:** Market (position 0), Organic shop (1), Drugstore (2).
  - **Categories:** Market: Produce (0) and Dairy (1). Organic shop: Produce (0). Drugstore: Cleaning (0).
  - **Items:**
    - Bell peppers: default Market, placed in Market/Produce and Organic shop/Produce.
    - Milk: Market, placed in Market/Dairy.
    - Oat milk: Market, placed in Market/Dairy.
    - Äpfel: Market, placed in Market/Produce.
    - Sponges: Drugstore, placed in Drugstore/Cleaning.
  - **Open entries:**
    - Alex's list: Bell peppers at Market, and "Burrito spice" unfiled.
    - Shared: Milk and Äpfel at Market.
    - BBQ Sat: Sponges at Drugstore.
    - Sam's list: Oat milk at Market.
    - Old party: Oat milk at Market.
  - **Bought entries:** Shared: Milk, bought 2026-10-27T09:00:00Z. Alex's list: Sponges, bought 2026-10-28T09:00:00Z.

- [ ] **Step 1: Write the failing tests**

```swift
// TextTests
@Test func cleanTextMatchesServer()
// "  Burrito \t spice " → "Burrito spice"; "" / "   " → nil; "a\u{0}b" → nil; 101 × "x" with max 100 → nil;
// decomposed "A\u{0308}pfel" → "Äpfel"; an emoji with U+200D passes unchanged
@Test func nameKeyAndFold() // nameKey(" MILK ") == nameKey("milk"); fold("Äpfel") == "apfel"

// ApplyTests (all on TestData.household, at = 2026-10-30T10:00:00Z)
@Test func entryAddUnfiledAndWithItem()   // unfiled "  oat   drink " → text "oat drink", storeId nil; itemId Sponges → text "Sponges", storeId Drugstore
@Test func entryAddExistingIdIsNoop()
@Test func entryBuyKeepsFirstTime()       // buy at t1, buy at t2 → boughtAt t1; unbuy → nil
@Test func readOnlyListUnchanged()        // Sam's list writable false: entry.add / entry.buy on it → snapshot unchanged
@Test func placeLinksExistingItemIgnoringCase() // unfiled "  milk " placed in Market/Dairy with newItemId N → itemId Milk, no item N
@Test func placeCreatesItemAndPlacement() // "Burrito spice" placed Market/Produce, N → item N "Burrito spice" default Market, placement (N, Market, Produce)
@Test func deletingStoreKeepsEntries()    // store.delete Market → every entry still there, Market ones with storeId nil; no Market categories or placements
@Test func deletingItemKeepsText()        // item.delete Milk → entries keep text "Milk", itemId nil
@Test func reorderKeepsUnlisted()         // store.reorder [Drugstore, Market] → Drugstore 0, Market 1, Organic shop 2
@Test func renameOntoTakenNameUnchanged() // item.update Milk name "OAT MILK" → unchanged; name "MILK" → "MILK"

// LarderTests (FakeTransport, LocalFiles in a temp directory, syncDelay .zero)
@Test func performPersistsBeforeShowing() // after perform: LocalFiles(dir).load().queue has the op; view shows its effect
@Test func queueSurvivesRelaunch()        // Review Focus 2: perform offline (transport throws), new Larder(same dir) → same pending, view shows the change
@Test func opsAddedDuringSyncSurvive()    // Review Focus 1: request 1 held open; perform op B; answer 200 for op A with a snapshot
                                          // without B → pending == [B], view shows B over the new snapshot; next request sends [B]
@Test func failedSyncKeepsSameOps()       // transport throws → pending unchanged with the same opIds, isOffline; then 200 → isOffline false, pending empty
@Test func longQueueSendsInOrderedBatches() // Review Focus 3: 1201 ops → requests of 500, 500, 201 ops, concatenated in queue order,
                                          // each sent after the previous answer
@Test func unauthorizedSignsOut()         // 3 pending, 401 → onSignedOut(3), snapshot/view nil, pending empty, files wiped
@Test func serverErrorKeepsQueue()        // 500 {"error":"internal"} → pending kept, isOffline true

// NoticesTests
@Test func hiddenListNotice()             // Review Focus 5: before has Sam's list, after lacks it and Sam is hidden, an entry.add on it rejected
                                          // forbidden → [.listHidden(ownerName: "Sam", lostChanges: true)]; without the rejection → lostChanges false
@Test func readOnlyNotice()               // forbidden on Sam's list, after shows it writable false → [.listReadOnly(ownerName: "Sam")]
@Test func renameConflictNotice()         // conflict on item.update Milk → "Bread" → [.renameConflict(from: "Milk", to: "Bread")]
@Test func quietCases()                   // not_found rejections → []; Sam removed (not in after.members) → no listHidden

// ContractTests
@Test(.enabled(if: Contract.isConfigured)) func larderRoundTrip()
// Larder with the admin client: perform entry.add on myList, await sync() → pending empty, snapshot has the entry
@Test(.enabled(if: Contract.isConfigured)) func privacyNoticesAgainstServer()
// Sam = Contract.newMember("Sam"): Sam's Larder performs member.set_privacy readonly, syncs; admin's Larder (synced before)
// performs entry.add on Sam's list, syncs → notices == [.listReadOnly(ownerName: Sam's name)], entry absent;
// Sam sets hidden; admin syncs → .listHidden(ownerName: Sam's name, lostChanges: false)
```

- [ ] **Step 2: Run the kit tests.** Expected: FAIL.
- [ ] **Step 3: Implement the five files** against the Interfaces.
- [ ] **Step 4: Run the kit tests, then `bash factory/checks.sh`.** Expected: PASS, with the contract tests run.
- [ ] **Step 5: Commit and push.** `git commit -m "Add the offline engine: local ops, queue, sync and notices"`. The `ios` run must be green.

**On your phone:** nothing new to see. Install it to make sure it still starts.

---

### Task 4: Signing in and out

**Files:**
- Create: `ios/PocketLarder/Keychain.swift`, `ios/PocketLarder/Main/SignedInView.swift` (a placeholder until Task 5), `ios/PocketLarder/Account/AccountView.swift`
- Modify: `AppModel.swift`, `PocketLarderApp.swift`, `Welcome/WelcomeView.swift`, `Welcome/EnterInviteView.swift`, `Localizable.xcstrings`, `ios/PocketLarderKit/Sources/PocketLarderKit/Larder.swift`
- Test: `ios/PocketLarderTests/AppModelTests.swift`, `ios/PocketLarderTests/KeychainTests.swift`, `ios/PocketLarderTests/Support/FakeTransport.swift` (a small copy for the app tests, including the `.hold` step), `ios/PocketLarderKit/Tests/PocketLarderKitTests/LarderTests.swift`

**Interfaces:**
- Consumes: `Invite`, `normalizeServer` (Task 1), `APIClient`, `APIError`, `Transport` (Task 2), `Larder`, `LocalFiles`, `Notice` (Task 3).
- Produces:
  - `public func close()` on `Larder`: ends this `Larder` for good, without waiting for a request in flight, because a forced sign-out is for a server that may never answer. It cancels the schedule. After it, `perform` and `sync()` do nothing, and the answer to a request in flight is dropped, whether it's a 200, `unauthorized` or any other error: no file is written or wiped, no state changes, `onSignedOut` isn't called and no further round runs. Without this, a 200 landing after a sign-out writes `snapshot.json` and `queue.json` back, and a late `unauthorized` wipes the files of the account signed in since.
  - `struct Account: Codable, Equatable, Sendable { var server: URL; var token: String; var memberId: String; var deviceId: String }`
  - `enum Keychain { static func load() -> Account?; static func save(_ a: Account) throws; static func delete() }`: one generic-password item with service `org.pocketlarder.account`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, and `kSecAttrSynchronizable = false`.
  - `AppModel(transport: any Transport = URLSessionTransport(), dataDirectory: URL = AppModel.defaultDataDirectory)` with:
    - `private(set) var account: Account?` and `private(set) var larder: Larder?`
    - `var signedOutLostChanges: Int?`, shown once on the welcome screen, then cleared.
    - `static var defaultDataDirectory: URL`: `Application Support/Larder`, created with `isExcludedFromBackup = true`.
    - `enum SignInError: Error, Equatable { case invalidInvite, rateLimited, unreachable(host: String), alreadySignedIn(name: String), other }`
    - `func signIn(_ invite: Invite, deviceName: String) async -> SignInError?`. It redeems, saves the `Account`, wipes the data directory, so that files left by a failed wipe never reach the new account, creates the `Larder` and awaits the first `sync()`. If the account is already signed in, it returns `.alreadySignedIn`.
    - `enum SignOutResult: Equatable { case done, unsentChanges(Int), unreachable }`
    - `func signOut(force: Bool) async -> SignOutResult`. Without `force` it syncs first, then:
      - returns `.unsentChanges(n)` if ops are still pending;
      - calls `POST /v1/signout` and wipes on success;
      - returns `.unreachable` when the server can't be reached.

      `force: true` wipes everything locally without asking the server and without waiting for a request in flight.

      Every wipe, here and in `Larder.onSignedOut`, is one step on the main actor with no `await` inside: `larder?.close()`, clear `larder` and `account`, delete the Keychain item, wipe the data directory.
    - `func open(_ url: URL)`: while signed in, an invite link shows the already-signed-in message instead of the form.
  - The root shows `WelcomeView` without an account and `SignedInView` with one. `Larder.onSignedOut` wipes the Keychain and the data, and sets `signedOutLostChanges`.
  - Sync triggers: becoming active, and every 60 seconds while active (a `.task` loop keyed on `scenePhase`).

Copy (exact English):
- `invalidInvite`: "This invite can't be used. It may have expired or been used already. Ask for a new one."
- `rateLimited`: "Too many sign-in attempts on this server. Try again in a minute."
- `unreachable`: "Can't reach %@."
- Already signed in: "This iPhone is already signed in as %@. Sign out first to use this invite."
- Signed out from elsewhere: "This iPhone was signed out." with " %lld changes that weren't sent yet are lost." added when the count is above 0, in plural forms.
- Sign-out with unsent changes: "%lld changes haven't been sent yet. Sign out and lose them?"
- Unreachable on sign-out: "Can't reach your server. Sign out anyway? This deletes everything on this iPhone. Ask an admin to remove this device from the household."
- `SignedInView` shows "Signed in as %@" and the account circle, which opens `AccountView` with only "Sign out" for now (Task 8 completes it).

- [ ] **Step 1: Write the failing tests** (`PocketLarderTests`, run on the simulator in CI)

```swift
@Test @MainActor func signInStoresAccountAndSyncs()
// fake: redeem 200 {token, member_id, device_id}, sync 200 (TestData-like snapshot) → Keychain.load() == model.account,
// model.larder?.snapshot != nil, the redeem body's device_name == "Kitchen iPhone"
@Test @MainActor func signInErrors()
// 401 invalid_invite → .invalidInvite; 429 → .rateLimited; transport throws → .unreachable(host: "lists.example.test")
@Test @MainActor func unauthorizedSyncSignsOut()
// signed in, 2 ops pending, sync answers 401 → account nil, Keychain.load() nil, data directory empty, signedOutLostChanges == 2
@Test @MainActor func signOutPaths()
// 1 pending and sync offline → .unreachable; force → .done and everything wiped;
// nothing pending, signout 204 → .done and the request was POST /v1/signout
@Test func keychainItemIsThisDeviceOnly()
// after save, SecItemCopyMatching with kSecReturnAttributes → kSecAttrAccessible == kSecAttrAccessibleWhenUnlockedThisDeviceOnly, not synchronizable
@Test func dataDirectoryIsExcludedFromBackup()
@Test @MainActor func inviteLinkWhileSignedIn() // signed in as "Alex": open(example link) → already-signed-in state with "Alex", account unchanged
@Test @MainActor func forcedSignOutDropsAnswerInFlight()
// sync held → signOut(force: true) returns .done while it's still held; release 200 → data directory still empty, account nil
@Test @MainActor func lateUnauthorizedSparesNextAccount()
// sync held, force sign-out, sign in again; release 401 for the old request → account is the new one, its files remain, signedOutLostChanges nil
@Test @MainActor func signInIgnoresLeftoverFiles()
// data directory holds snapshot.json and queue.json with 1 op; signIn → the first sync request sends no ops, model.larder?.pending is empty
```

And in the kit's `LarderTests` (the Docker command in AGENTS.md runs them):

```swift
@Test @MainActor func closeDropsAnswerInFlight()
// sync held, close(), files.wipe(); release 200 → snapshot.json and queue.json don't exist, no further request
@Test @MainActor func closeDropsUnauthorizedInFlight()
// 1 op, sync held, close(); release 401 → onSignedOut not called, queue.json still there
@Test @MainActor func closedLarderDoesNothing()
// perform, close(): no request after syncDelay; sync() sends nothing; perform writes no queue.json after a wipe
```

- [ ] **Step 2: Implement** against the Interfaces. Each test cleans the Keychain item before it starts.
- [ ] **Step 3: Add the screenshot** `welcome-signed-out-<lang>-<appearance>`, launched with the Debug-only argument `-signedOutLostChanges 2`, plus `enter-invite-error-<lang>-<appearance>` with the `invalidInvite` message, launched with `-inviteError invalidInvite` in Debug.
- [ ] **Step 4: Commit and push.** `git commit -m "Sign in with an invite, keep the token in the Keychain, sign out"`. The `ios` run must be green. Look at the new screenshots.
- [ ] **Step 5: README.** Add "Signing in" to "The iOS app": open the invite link on the iPhone (from a message or the QR code), or enter it by hand under "Enter invite". Also say to update the server before installing the app: an older server answers a request that lost its `Authorization` header with `unauthorized`, which makes the app sign out and delete its data. Commit with the code.

**On your phone:**
- Get an invite with `pocketlarder invite <you>`, send it to yourself and tap it. The form is filled. Sign in, and it says "Signed in as <you>".
- Try the same invite again on the other phone. It says the invite can't be used.
- Turn on Airplane Mode, close and reopen the app. You're still signed in.
- Sign out. You're back on the welcome screen.

---

### Task 5: The main screen and adding

**Files:**
- Create (package): `Sources/PocketLarderKit/Shelf.swift`, `Sources/PocketLarderKit/Adding.swift`. Test: `ShelfTests.swift`, `AddingTests.swift`
- Create (app): `Main/MainView.swift`, `Main/ListSwitcher.swift`, `Main/StoreChips.swift`, `Main/EntryRow.swift`, `Main/EntryTile.swift`, `Main/RecentlyBought.swift`, `Main/EditEntrySheet.swift`, `Main/AddBar.swift`, `Main/NoticeBanner.swift`, `Main/OfflineBadge.swift`, `ListColor+Color.swift`, `Fixtures/household.json`, `Fixtures/FixtureTransport.swift` (Debug only)
- Delete: `Main/SignedInView.swift`
- Modify: `AppModel.swift`, `PocketLarderApp.swift`, `Localizable.xcstrings`
- Test: `PocketLarderTests/NoticeTextTests.swift`, `PocketLarderUITests/ScreenshotTests.swift`

**Interfaces:**
- Consumes: `Snapshot` and its lookups (Task 2); `Larder`, `fold`, `cleanText`, `nameKey`, `Notice` (Task 3); `AppModel`, `AccountView` (Task 4).
- Produces, in `Shelf.swift`:
  - `enum Scope: Hashable, Sendable { case myView, list(String) }` and `enum StoreFilter: Hashable, Sendable { case all, store(String) }`
  - `struct CategoryGroup: Equatable, Sendable { let category: Category; let entries: [Entry] }`, `struct StoreSection: Equatable, Sendable { let store: Store; let groups: [CategoryGroup] }`, and `struct Shelf: Equatable, Sendable { let notFiled: [Entry]; let stores: [StoreSection]; let recentlyBought: [Entry] }`
  - `func shelf(_ s: Snapshot, scope: Scope, filter: StoreFilter) -> Shelf`:
    - My view is my list plus every non-archived shared list.
    - `notFiled` holds the open entries that `isFiled` rejects; under `.store(S)` only those whose `storeId` is nil or S.
    - `stores` holds the filed open entries, by store position, then category position, then `fold(text)`, then id. Empty stores and categories are left out. `.store(S)` keeps only S.
    - `recentlyBought` holds the bought entries in scope, under `.store(S)` only those at S, newest first.
  - `func isFiled(_ e: Entry, in s: Snapshot) -> Bool`: it has an item, a store, and a placement for that pair.
  - `func tag(for e: Entry, in s: Snapshot) -> ListInfo?`: the entry's list when it's shared, otherwise nil.
  - `func switcherLists(_ s: Snapshot) -> [ListInfo]`: non-archived shared lists by `fold(name)`, then other members' personal lists by owner name.
  - `func addTargets(_ s: Snapshot) -> [ListInfo]`: my list, then writable non-archived shared lists, then writable other personal lists.
  - `func validScope(_ scope: Scope, in s: Snapshot) -> Scope`: `.myView` when the list is missing or archived.
- Produces, in `Adding.swift`:
  - `struct Suggestion: Equatable, Sendable { let item: Item; let store: Store?; let category: Category? }`
  - `func suggestions(_ s: Snapshot, for query: String, limit: Int = 8) -> [Suggestion]`: items whose `fold(name)` starts with `fold(query)`, then those that contain it, each group alphabetical by `fold(name)`. The store is the item's default store, and the category its placement there. A query that cleans to nothing gives `[]`.
  - `enum AddOutcome: Equatable, Sendable { case add(Op), existing(Entry) }`
  - `func add(_ item: Item, to listId: String, in s: Snapshot) -> AddOutcome`: `.existing` when that item is already open on the list, otherwise `.add(Op(.entryAdd, id: newID(), listId:, itemId:))`.
  - `func add(text: String, to listId: String, in s: Snapshot) -> AddOutcome?`: nil when `cleanText(text, max: Limit.name)` is nil. A catalog item with an equal `nameKey` is added with `add(_:to:in:)`. Anything else becomes `.add` of an unfiled `entry.add` with the cleaned text.
- Produces (app):
  - `AppModel.scope: Scope` and `AppModel.addTarget: String?` (nil means my list). Both reset on launch and when the app becomes active after more than 5 minutes in the background.
  - `@AppStorage("layout")`.
  - `Color(_ token: ListColor)`.
  - `FixtureTransport` (Debug): `-fixture household` makes `AppModel` sign in to `https://fixture.invalid` without the Keychain. `POST /v1/sync` applies the received ops to its copy of `household.json` with `applying` and answers with it. Later tasks add routes.
  - `func noticeText(_ n: Notice) -> String` (localized) in `NoticeBanner.swift`.

Behavior and copy, from the design's "The main screen", "Sync feedback" and the mockups:
- **List switcher** (`switcher-label.html` option 1, no subtitle): a tinted capsule with the scope's name and "▼". Its menu lists My view, the switcher lists (color dot, lock when read-only), and personal lists named "%@'s list". "Lists…" and "Stores & items…" come in Task 6.
- **Account circle** with the member's initial opens `AccountView`. `OfflineBadge` sits next to it.
- **Store chips:** "All", then each store with entries in scope.
- **Rows** (`store-view.html` A): a cross-off circle with a 44-point target, the text with the note under it, the quantity, and the tag of a shared list. Tapping the row opens `EditEntrySheet` (quantity limited to `Limit.quantity`, note to `Limit.note`, Delete). Swiping offers Delete only.
- **Tiles** (C): two columns, and one column at accessibility text sizes. Tapping a tile crosses it off. Its context menu has Edit and Delete.
- **VoiceOver actions:** "Cross off" and "Delete".
- **"Not filed yet"** is a section at the top.
- **"Recently bought (%lld)"** sits at the end and expands. Tapping an entry there puts it back (`entry.unbuy`).
- **Add bar** (`add-flow.html` B): the field "Add item…" and the black target button with the target's name ("My list", the shared list's name, "%@'s list") and a menu of `addTargets`.
  - Typing shows `suggestions` above the bar, with the item's name and "Store · Category".
  - A suggestion or return adds: `.existing` scrolls to the entry and highlights it, and nil changes nothing.
  - The field clears after adding and keeps focus.
  - Viewing a single list makes it the target. A read-only list shows the bar disabled with "%@'s list is read-only."
- **Pull to refresh** runs `larder.sync()`. When `validScope` changes the scope, the app switches to My view.
- **The notice banner** shows `larder.notices.first` below the top bar. It never covers the list, goes away after 6 seconds or with a tap (`dismissNotice()`), and is announced to VoiceOver.
- **Notice copy:**
  - `.listHidden`: "%@'s list is now hidden, so it's no longer on this iPhone.", plus " Your recent changes to it weren't saved." when `lostChanges`.
  - `.listReadOnly`: "%@'s list is now read-only. Your recent changes to it weren't saved."
  - `.renameConflict`: "Couldn't rename "%@" to "%@": that item already exists."
- **Offline popover:** "Not connected. %lld changes will be sent when your server is reachable."

- [ ] **Step 1: Write the failing kit tests**

```swift
// ShelfTests (TestData.household)
@Test func myViewMergesOwnAndShared()      // entries from Alex's list, Shared, BBQ Sat; none from Sam's list or Old party
@Test func walkingOrder()                  // stores Market, Drugstore; Market groups Produce [Äpfel, Bell peppers], Dairy [Milk]
@Test func notFiledRules()                 // "Burrito spice" in notFiled; an entry whose item has no placement in its store is notFiled;
                                           // under .store(Drugstore) notFiled holds Burrito spice (no store) but not a Market one
@Test func recentlyBoughtNewestFirst()     // My view → [Sponges (10-28), Milk (10-27)]; .store(Drugstore) → [Sponges]
@Test func switcherAndTargets()            // switcher: BBQ Sat, Shared, Sam's list; Sam read-only → still in switcher, not in addTargets
@Test func hiddenScopeFallsBackToMyView()  // Review Focus 5: validScope(.list(Sam's list)) on a snapshot without it → .myView; archived → .myView

// AddingTests
@Test func suggestionsPrefixFirst()        // "mil" → [Milk, Oat milk]; "äp" and "ap" → [Äpfel] with store Market, category Produce
@Test func addingExistingOpenItemShowsIt() // add(Bell peppers, to: Alex's list) → .existing(that entry); to Shared → .add(entry.add itemId Bell peppers)
@Test func returnOnExistingName()          // add(text: " MILK ", to: Alex's list) → .add with itemId Milk, no text
@Test func unfiledAndTooLong()             // "Birthday candles" → .add unfiled with that text; 101 characters → nil; "   " → nil
```

- [ ] **Step 2: Run the kit tests.** Expected: FAIL. Then implement `Shelf.swift` and `Adding.swift`, and run them until they PASS.
- [ ] **Step 3: Implement the screens** and `FixtureTransport` against the Interfaces and the behavior above. `household.json` holds at least 15 open entries over three stores, two shared lists, a read-only list of Sam's, one unfiled entry and five bought entries.
- [ ] **Step 4: Write the app tests**

```swift
@Test func noticeTexts() // English text of each Notice case equals the copy above, with "Sam", "Milk", "Bread"
// ScreenshotTests, with -fixture household, en/de × light/dark:
func testMain()          // main-<lang>-<appearance>-rows and -tiles (All); main-store-… (Market chip); main-bought-… (expanded)
func testAdding()        // typing "mi" → add-suggestions-…; tapping Milk adds it (it appears under Market/Dairy)
func testEditAndReadOnly() // edit sheet → edit-entry-…; switching to Sam's list → readonly-…
```

- [ ] **Step 5: Commit and push.** `git commit -m "Add the main screen: My view, store order, crossing off and adding"`. The `ios` run must be green. Check every screenshot against `store-view.html` (A and C), `add-flow.html` (B) and `switcher-label.html` (1).

**On your phone:** (two phones, both signed in)
- Add three things to your list. They appear under "Not filed yet". Cross one off. It moves to "Recently bought", and tapping it there brings it back.
- Tap an entry, set the quantity "2" and a note, then delete another with a swipe.
- Airplane Mode: cross off two entries, close the app fully, reopen it. They're still crossed off. Turn Airplane Mode off and pull to refresh. They stay crossed off, and the other phone shows them crossed off after its next sync.
- Switch to the other member's list with the capsule, then leave the app for more than 5 minutes. You're back on My view.
- Turn on the largest text size (Settings > Accessibility > Display & Text Size). Everything is still readable and tappable.

---

### Task 6: Lists, stores and items

**Files:**
- Create: `ios/PocketLarder/Setup/ListsView.swift`, `Setup/StoresView.swift`, `Setup/StoreDetailView.swift`, `Setup/ItemsView.swift`, `Setup/ItemDetailView.swift`
- Modify: `Main/ListSwitcher.swift` (add "Lists…" and "Stores & items…"), `Localizable.xcstrings`
- Test: `PocketLarderUITests/ScreenshotTests.swift`

**Interfaces:**
- Consumes: `Larder.perform`, `Op` and its types (Task 2), `fold` (Task 3), `ListColor` and `Color(_:)` (Task 5).
- Produces: the setup screens. No new package API: each change is a single `Op` sent through `larder.perform`. A reorder sends the full new id order (`store.reorder`, or `category.reorder` with `storeId`).

Behavior, from the design's "My account and the other screens" and `settings.html` card 3:
- **Lists…:**
  - The shared lists, with the color dot.
  - Create: a name and a color picker with the nine tokens.
  - Rename, recolor and archive.
  - An "Archived" section with Restore.
- **Stores & items…:** tabs "Stores" and "Items".
- **Stores tab:**
  - The stores in position order with drag handles, under the header "In the order you shop", and "Add store".
  - A store opens to rename it, delete it, and add, rename, delete and drag its categories.
  - The delete confirmation: "Delete %@? Its categories go too. Entries filed there move to Not filed yet."
- **Items tab:**
  - A search field, no heading.
  - Each item as name and "%@ · %@", plus ", also at %lld other stores" when it is placed in other stores as well.
  - An item opens to:
    - rename it;
    - pick its usual store (`item.update defaultStoreId`, with "None" sending `""`);
    - pick the category in each store (`item.place`);
    - delete it, with the confirmation "Delete %@? Entries keep their name and move to Not filed yet."
- **Names** go through `cleanText(…, max: Limit.name)`. Save stays disabled while it returns nil.

- [ ] **Step 1: Implement the screens** against the behavior above.
- [ ] **Step 2: Write the screenshot tests:** `lists-…`, `stores-…`, `store-detail-…`, `items-…`, `item-detail-…`, all in en/de × light/dark, on `-fixture household`.
- [ ] **Step 3: Commit and push.** `git commit -m "Add list, store and item setup"`. The `ios` run must be green. Check the screenshots against `settings.html` card 3.

**On your phone:**
- Create the shared list "Shared" in a color. It shows on the other phone, and entries on it carry the tag in My view.
- Create your stores in round-trip order, each with a few categories, and drag them into order. The chips follow that order.
- Archive the shared list, then restore it.

---

### Task 7: Moving and filing

**Files:**
- Create (package): `Sources/PocketLarderKit/Moving.swift`. Test: `MovingTests.swift`
- Create (app): `Main/MoveMenu.swift`, `Main/CategoryPicker.swift`
- Modify: `Main/EntryRow.swift`, `Main/EntryTile.swift`, `Localizable.xcstrings`
- Test: `PocketLarderUITests/ScreenshotTests.swift`

**Interfaces:**
- Consumes: `Snapshot` lookups, `Op` (Task 2), `isFiled` (Task 5).
- Produces:
  - `enum MoveOutcome: Equatable, Sendable { case place(Op), needsCategory }`
  - `func move(_ e: Entry, to storeId: String, category: String? = nil, in s: Snapshot) -> MoveOutcome`:
    - For an entry with an item and a placement at `storeId`, or a given `category`: `.place(entry.place {id, storeId, categoryId?})`.
    - For an entry with an item but neither: `.needsCategory`.
    - For an unfiled entry (no item): `.needsCategory` without a `category`, otherwise `.place` with `categoryId` and `newItemId: newID()`.

Behavior, from `move-to-store.html` option B and the design:
- **The ⇄ button** sits at the trailing edge of every row and in a tile's corner. It has a 44-point target and the VoiceOver label "Move %@ to another store". The rows also get a VoiceOver action "Move to store".
- **The store menu** lists the stores in position order, with the entry's store checked. Choosing the checked store does nothing.
- **`.needsCategory`** opens `CategoryPicker` for that store: its categories in order, plus "New category…". A new category sends `category.create` (`id: newID()`) followed by the `entry.place` in one `perform` call.
- **Filing an unfiled entry** uses the same button.

- [ ] **Step 1: Write the failing kit tests**

```swift
@Test func moveToStoreWithPlacement()   // Bell peppers (Market) → Organic shop → .place, storeId Organic shop, categoryId nil
@Test func moveNeedsCategoryOnce()      // Milk → Organic shop → .needsCategory; with category Organic Produce → .place with that categoryId
@Test func fileUnfiled()                // Burrito spice → Market → .needsCategory; with Produce → .place with categoryId Produce
                                        // and newItemId a fresh lowercase UUID (two calls give different ids)
```

- [ ] **Step 2: Run the kit tests.** Expected: FAIL. Then implement `Moving.swift`, and run them until they PASS.
- [ ] **Step 3: Implement the button, the menu and the picker.** Screenshots: `move-menu-…` (the menu open on Bell peppers), `category-picker-…`, and `main-…-tiles` regenerated with ⇄.
- [ ] **Step 4: Commit and push.** `git commit -m "Move entries between stores and file unfiled ones"`. The `ios` run must be green.

**On your phone:**
- Add "Bell peppers" (unfiled). Tap ⇄, pick a store, pick a category. It moves under that store and category.
- Tap ⇄ again and pick another store. You're asked for the category once. Move it back: no question.
- On the other phone, type "bell". The suggestion shows its store and category. Add it there: it's the same item, not a second one.
- Rows and tiles both have the ⇄ button, and VoiceOver reads "Move Bell peppers to another store".

---

### Task 8: My account and adding a device

**Files:**
- Modify: `ios/PocketLarder/Account/AccountView.swift`, `Fixtures/FixtureTransport.swift` (add `POST /v1/invites` and `POST /v1/invites/revoke`), `Localizable.xcstrings`
- Create: `ios/PocketLarder/Account/AddDeviceSheet.swift`, `ios/PocketLarder/Account/QRCode.swift`
- Test: `PocketLarderTests/QRCodeTests.swift`, `PocketLarderUITests/ScreenshotTests.swift`

**Interfaces:**
- Consumes: `AppModel.signOut(force:)` (Task 4), `Larder.perform`, `APIClient.createInvite`, `revokeInvites` (Task 2).
- Produces:
  - `func qrImage(_ text: String) -> UIImage?` in `QRCode.swift` (`CIFilter.qrCodeGenerator`, correction level "M", scaled without interpolation).
  - `AddDeviceSheet(invite: CreatedInvite, memberName: String)`. Task 9 reuses it for other members.

Behavior, from `settings.html` cards 1–2:
- **My account:** a header with the initial, the name, an "Admin" badge, and the server's host.
- **List layout:** Rows or Tiles. **Appearance:** System, Light or Dark.
- **"Who can see my list":** Open, Read-only, Hidden, which sends `member.set_privacy`. The footer is exact: "Hidden isn't encryption: whoever runs your server can read every list. Filing an entry puts its name in the shared catalog, where others see it in suggestions. Leave it unfiled to keep it private."
- **"This iPhone":**
  - "Add a device…".
  - "Language", showing the current language's name and opening `UIApplication.openSettingsURLString`.
  - "Sign out", which handles the three `SignOutResult` cases from Task 4, with their dialogs.
- **Add a device:**
  - `createInvite()`, then the QR code with "Scan with the new iPhone's Camera".
  - "Signs in as %@ · one use · valid until %@", with the expiry formatted relative to now.
  - "Share invite…" (`ShareLink`).
  - "Copy invite", which writes the pasteboard with `.localOnly: true` and `.expirationDate` 10 minutes ahead.
  - The warning "Anyone with this invite can sign in as you until it's used or expires. Only send it to yourself."
  - "Cancel invite" (`revokeInvites()`), which closes the sheet.
- **Offline:** each network action shows "Needs a connection to your server".

- [ ] **Step 1: Write the failing test**

```swift
@Test func qrCodeEncodesInviteURL() // CIDetector(ofType: CIDetectorTypeQRCode) on qrImage(example) finds one feature whose messageString == example
```

- [ ] **Step 2: Implement** against the Interfaces and the behavior.
- [ ] **Step 3: Screenshots:** `account-…`, `add-device-…`, in en/de × light/dark. The fixture's invite URL is a dummy, so no real code shows in an image.
- [ ] **Step 4: Commit and push.** `git commit -m "Complete My account: layout, appearance, privacy, language, add a device"`. The `ios` run must be green.

**On your phone:**
- Switch Rows/Tiles and System/Light/Dark. The list follows at once.
- Set your list to Read-only. The other phone can see it but can't add to it, and it says so. Set Hidden. It disappears from the other phone with the notice. Set Open again.
- Add a device: show the QR code and scan it with the other phone's Camera app. iOS offers to open PocketLarder, which says that phone is already signed in. Then tap Cancel invite.
- Language opens Settings. Choose Deutsch: the app is German.
- Sign out in Airplane Mode with something unsent. You're asked first, and "Sign out anyway" works.

---

### Task 9: Admin: members and devices

**Files:**
- Modify (package): `Sources/PocketLarderKit/API.swift`. Test: `APIClientTests.swift`
- Create (app): `ios/PocketLarder/Admin/MembersView.swift`, `Admin/MemberDetailView.swift`, `Admin/InviteMemberSheet.swift`
- Modify: `Account/AccountView.swift` (the "Household" section for admins), `Fixtures/FixtureTransport.swift` (add `GET /v1/admin/members`, `PATCH`, the `DELETE`s and invites for members), `Localizable.xcstrings`
- Test: `PocketLarderUITests/ScreenshotTests.swift`

**Interfaces:**
- Consumes: `APIClient` admin methods (Task 2), `AddDeviceSheet` (Task 8), `AppModel` sign-out handling (Task 4).
- Produces: `extension APIClient { func removeDevice(_ deviceId: String, revokingInvitesOf memberId: String) async throws(APIError) }`. It calls `removeDevice`, then `revokeInvites(memberId:)`.

Behavior, from `settings.html` card 4 and the design:
- **The "Household" section** shows "Members & devices" only when `snapshot.me.isAdmin`.
- **The members list:** each member's name, an "Admin" badge, and either each device as "%@ · %@" (name, last seen relative to now) or "Invited, not signed in yet". Pull to refresh reloads it.
- **"Invite a new member…"** asks for a name (`cleanText`, max 100), calls `createInvite(newMemberName:)`, and shows `AddDeviceSheet` for that name.
- **A member's page:**
  - The Admin switch (`setAdmin`).
  - Each device with "Sign out", whose confirmation says: "Sign out %@? Their pending invites are cancelled too." It calls `removeDevice(_:revokingInvitesOf:)`.
  - "Add a device for %@…" (`createInvite(memberId:)`).
  - "Remove %@…", whose confirmation says: "Remove %@? All their devices are signed out and their list is deleted."
- **Your own device or yourself:** removing either goes through the Task 4 signed-out path.
- **After every change** the list reloads and `larder.sync()` runs.
- **Errors:**
  - `conflict`: "Someone in the household already has that name."
  - `last_admin`: "The household needs at least one admin."
  - Offline: "Needs a connection to your server".

- [ ] **Step 1: Write the failing kit test**

```swift
@Test func removingDeviceAlsoRevokesInvites()
// FakeTransport: removeDevice(d, revokingInvitesOf: m) → requests DELETE /v1/admin/devices/d, then POST /v1/invites/revoke {"member_id": m}
```

- [ ] **Step 2: Run the kit tests.** Expected: FAIL. Implement it, and run them until they PASS.
- [ ] **Step 3: Implement the screens.** Screenshots: `members-…`, `member-detail-…`, `invite-member-…`, in en/de × light/dark.
- [ ] **Step 4: Commit and push.** `git commit -m "Add the admin area: members, devices and invites"`. The `ios` run must be green.

**On your phone:** (as an admin)
- Members & devices lists both of you with your phones and when they were last seen.
- Invite a new member "Test". They show as "Invited, not signed in yet". Remove them.
- Make your partner an admin, then remove it again. Trying to remove your own admin rights as the only admin says the household needs an admin.
- Add a device for your partner and cancel it.

---

## Owner's Mac setup guide

Claude writes it right after Task 1 merges, because it depends on Task 1's files. It goes to `~/pocketlarder-mac-setup.md` on the factory machine, outside the repo and never committed. It's also offered as a private page that opens on the Mac. It's for someone who has never built an Apple app, and covers:

- **Xcode:**
  - Check that macOS is new enough for Xcode 27.
  - Install Xcode 27 from the App Store.
  - On first launch, add the iOS 27 platform.
- **Signing:**
  - Sign in with your Apple ID under Xcode > Settings > Accounts, which makes a free "Personal Team".
  - Clone the repo.
  - Copy `ios/Config/Local.xcconfig.example` to `Local.xcconfig`.
  - Find your team ID and enter it there, with a bundle ID only you use (`com.<yourname>.pocketlarder`).
- **Each iPhone:**
  - Connect it by cable and trust the Mac.
  - Turn on Developer Mode (Settings > Privacy & Security), which restarts the phone.
  - Choose the phone as the run destination and press Run.
  - Trust the developer profile on the phone (Settings > General > VPN & Device Management).
  - Repeat for the second phone.
- **Keeping it running:**
  - Free installs stop working after 7 days: reconnect the phone and press Run again.
  - Updating after a merge: `git pull`, then Run.
  - Free accounts allow 3 such apps per phone.
- **When something goes wrong:** the usual errors (untrusted developer, a bundle ID already in use, the device not showing up) and what each one means.
