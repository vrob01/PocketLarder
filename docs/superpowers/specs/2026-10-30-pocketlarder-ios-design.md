# PocketLarder iOS app design

Date: 2026-10-30. Status: approved by the owner on 2026-10-30, together with the mockups.

This document comes out of a second interview with the owner, about the iOS app.
It builds on the product spec, `2026-10-27-pocketlarder-design.md`, which stays
in force: everything it says about the app still holds unless this document
says otherwise. The server contract is `server/API.md`. Where this document and
the product spec disagree about the app, this document wins.

Markers work as in the product spec: statements without a marker are the
owner's decisions, and **[Claude's call]** marks a choice Claude made that the
owner heard but didn't make. Mockups from this interview are in
`2026-10-30-pocketlarder-ios-mockups/`.

## Intent

The server is running. The app is what the household actually touches, so it
decides whether PocketLarder replaces KitchenOwl. It has to fix the five
problems in the product spec's Intent, look and feel like a modern iPhone app,
and stay simple enough for the owner's partner, who rejects anything that feels
complicated.

## Changes to the product spec

- **Moving to another store** uses a move button on every row, not a swipe
  action. This replaces "swipe on the entry and choose Move to store".
- **Catalog items** are managed under "Stores & items", reached from the list
  switcher, not in the settings **[Claude's call]**.
- **A Language row** in My account opens the app's page in the iPhone's
  Settings app. It isn't a preference of the app's own (see Language).

## Goals

- The factory builds the whole app on the Linux factory machine. The owner only
  installs it from the Mac and tests it on the phone.
- Quality is no worse than if it were built at a Mac. Logic is fully tested,
  and every screen is reviewed from real simulator screenshots.
- English and German from the first release, ready for more languages.
- Every screen in the mockups, with the behavior in the product spec.

## Non-goals

- iPad layouts. The app is for iPhone **[Claude's call]**. It works in portrait
  and landscape without a special landscape layout.
- An in-app QR scanner. The iPhone's Camera app opens invite links
  **[Claude's call]**. To be confirmed on the owner's phone.
- A language setting inside the app.
- OIDC sign-in. That's plan 3. The sign-in screen is shaped so it can be added
  (see Signed out).

## Anti-goals

- Any third-party code: no libraries, no analytics, no crash reporting.
  Networking, Keychain and QR codes come from Apple's frameworks
  **[Claude's call]**. This backs up the welcome screen's privacy promise.
- A change made on the phone that a sync undoes ("items popping back").
- A notice or dialog that blocks the list while shopping.

## How it gets made

- The factory builds the app, one GitHub issue per piece, the same way it built
  the server. The owner writes no code.
- After each piece is merged, the owner installs it on the phone and runs a
  short checklist that comes with the piece's pull request. Anything that's off
  becomes a new factory issue, so the factory never waits on the owner.
- **Logic in a Swift package** **[Claude's call]**: everything that isn't a
  screen (data model, sync, the offline queue, applying changes locally,
  sorting and grouping, search, invite parsing, talking to the server) lives in
  a Swift package under `ios/` that builds and tests on Linux. The factory runs
  it in Swift's official Docker image, so it needs no Swift install on the
  factory machine.
- **Contract tests against the real server** **[Claude's call]**: the package's
  tests include a set that runs against a real `go run . serve` with a fresh
  data directory, so the app and the server are checked against each other,
  not only against `API.md`.
- **The app itself** (screens, Keychain, opening `pocketlarder://` links, QR
  codes, the share sheet) only builds on macOS. Its build and tests run on
  GitHub Actions macOS runners. The repo is public, so these runs are free. The
  `xcode-27` runner label carries Xcode 27 with the iOS 27 SDK (generally
  available since 2026-10-15, Apple silicon only).
- **Screenshots for review** **[Claude's call]**: every CI run renders each
  screen in the simulator with sample data, in light and dark, rows and tiles,
  English and German, and uploads the images as run artifacts. The factory's UI
  and UX reviewers judge the screens from them.
- **Factory changes, made by hand** **[Claude's call]**: `factory/*` and
  `.claude/*` are protected from factory jobs, so before the first iOS piece
  they are changed outside the factory, by the owner or in a session with
  Claude:
  - `factory/checks.sh` runs the Swift package's tests, contract tests
    included, on every branch that touches `ios/` or `server/`, so a server
    change can't break the app unnoticed. On a branch that touches `ios/` it
    also waits for that commit's GitHub Actions run and fails unless it passed.
    Branches that touch neither, such as docs-only ones, stay as fast as now.
  - The gate's other callers learn to wait for CI as well. A macOS run doesn't
    fit in the 10 minutes one command may take, which affects both the
    builder's stop hook and the orchestrator's gate call. The merge gate runs
    on a local merge commit that GitHub never builds. So `factory/bin/gate`,
    `factory/bin/job` and the factory skill change together with `checks.sh`,
    and the plan decides how the merge step gets a CI result.
  - The builder learns to read failed CI logs, and the UI and UX reviewers
    learn to fetch the screenshot artifacts.
  - The GitHub Actions workflow lands by hand with these changes, and
    `.github/*` joins `protected_paths`, which now refuse additions too. No
    factory branch ever writes or weakens the checks it's judged by.
- **The Xcode project** is kept in a form the factory can edit without Xcode,
  with the project's folders synchronized to disk, so adding a source file
  never touches the project file **[Claude's call]**.
- **Signing stays on the Mac** **[Claude's call]**: the Apple ID team and the
  bundle ID live in a small settings file on the Mac that's never committed, so
  installing never leaves changes in git. A free Apple ID needs a bundle ID
  nobody else has used, which is why the repo can't fix one. CI builds for the
  simulator without signing.
- **The Mac setup guide**, for someone who has never built an Apple app (Xcode,
  signing with a free Apple ID, installing on both phones, reinstalling every 7
  days), is written for the owner only and is never committed, from the
  product spec.

## Signed out

Mockups: `welcome.html` (its first two cards) and `enter-invite.html`.

### Welcome screen

Shown on launch whenever the device has no token.

- The logo and the name, PocketLarder.
- A short text saying this iPhone needs an invite: "Shopping lists for your
  household. To start, this iPhone needs an invite from someone in your
  household: scan its QR code with the Camera app."
- An "Enter invite" button, for when tapping a `pocketlarder://` link doesn't
  open the app.
- A "Set up your own server" link that opens the README's self-hosting section
  in Safari (`https://github.com/vrob01/PocketLarder#self-hosting`).
- A footer: "Open source and private. No tracking, no ads, no analytics. Your
  lists are stored only on your household's own server." **[Claude's call]**:
  the owner asked for "no data is gathered, sold or sent anywhere". The lists
  do go to the household's server, so the wording says where they go instead.

### Enter invite

- Three fields: **Server**, **Invite code** and **Device name**, plus a "Paste
  invite" button in the top bar. People receive an invite as one link, so
  "Paste invite" splits it into the fields, and pasting the whole link into any
  field does the same **[Claude's call]**. The paste button is the system's own,
  which reads the clipboard without iOS's paste permission prompt.
- Opening a `pocketlarder://invite` link lands here with all three fields
  filled in, so one tap on Sign in finishes it.
- **Server** shows `https://` in front. A bare host like `lists.example.com`
  gets `https://` added. The app refuses anything but `https://`, except
  `http://localhost` and `http://127.0.0.1` with an optional port, the same
  rule the server applies to its public URL. A path, query or fragment is
  refused. A trailing `/` is dropped.
- **Invite code** is one line in a monospace font, cut off at the end.
- **Device name** starts as "iPhone" (iOS no longer gives apps the phone's own
  name) with the hint "Shows in your household's device list, e.g. "Sam's
  iPhone"." **[Claude's call]**.
- Sign in stays disabled until server and code are filled in.
- Errors, shown under the form **[Claude's call]**:
  - `invalid_invite`: "This invite can't be used. It may have expired or been
    used already. Ask for a new one."
  - `rate_limited`: "Too many sign-in attempts on this server. Try again in a
    minute."
  - No connection: "Can't reach lists.example.com."
- If an invite link opens the app while it's signed in: "This iPhone is
  already signed in as Alex. Sign out first to use this invite."
  **[Claude's call]**.
- The separate server field is also what OIDC sign-in (plan 3) will need.

## The main screen

Mockups: `switcher-label.html` (option 1), `move-to-store.html` (option B) and
the product spec's `store-view.html` (layouts A and C).

- **List switcher, top left:** the current view's name in a tinted capsule with
  an arrow ("My view ▼"), so it reads as a button, not a header. No subtitle.
  Its menu has:
  - My view, every non-archived shared list (with its color dot), and every
    other member's personal list the server sends ("Sam's list", with a lock
    when read-only);
  - then "Lists…" and "Stores & items…".
- **Account circle, top right:** the member's initial. It opens My account.
- **Store chips, sections, rows and tiles, "Not filed yet" and recently
  bought** are as in the product spec and its mockups.
- **Move button ⇄ on every row.** One tap shows the stores in round-trip order
  with the current one checked, and a second tap moves the entry. If the item
  has no category in that store yet, the app asks for one once and remembers it
  as the item's placement there (from the product spec). Moving changes only
  that entry, not the item's usual store, which is how `entry.place` works.
  **[Claude's call]**:
  - On a "Not filed yet" entry, the same button files it: pick the store, then
    the category.
  - In the tiles layout, the button sits in each tile's corner.
- **On a row:** tapping the circle (rows) or the tile (tiles) crosses the entry
  off, and tapping the row edits quantity and note (from the product spec).
  **[Claude's call]**: swiping a row offers only Delete.
- **Add bar:** as in the product spec and its `add-flow.html` option B. The
  black button shows which list new items go to. **[Claude's call]**:
  - Viewing a single list makes that list the add target.
  - A read-only list shows a disabled add bar that says so, and never appears
    in the add bar's list picker.
  - Pressing return on text that matches a catalog item's name, ignoring case,
    adds that item rather than an unfiled entry.
  - Search ignores case and accents, so "apfel" finds "Äpfel".
- The switcher and the add target both reset to My view and the personal list
  on launch and after more than 5 minutes in the background (from the product
  spec).

## Sync feedback

All of this is **[Claude's call]**, except the hidden-list notice, which the
owner asked for.

- A change the server refuses leaves the phone when the next snapshot arrives,
  as `API.md` requires. That's intended.
- **Notices** appear as a banner below the top bar that never covers the list.
  It goes away after a few seconds or with a tap, and VoiceOver reads it out.
  - A list that was visible and is now missing while its owner is still a
    member: "Sam's list is now hidden, so it's no longer on this iPhone." If
    changes to it were refused, the notice adds "Your recent changes to it
    weren't saved." If that list was on screen, the app switches to My view.
  - Changes refused `forbidden` on a list that's now read-only: "Sam's list is
    now read-only. Your recent changes to it weren't saved."
  - An item rename refused `conflict`: "Couldn't rename "Milk" to "Bread": that
    item already exists."
  - Refusals for things already deleted elsewhere (`not_found`) stay silent.
- **Offline:** while the last sync attempt failed for lack of a connection or a
  server error, a small crossed-out cloud sits next to the account circle.
  Tapping it says "Not connected. 3 changes will be sent when your server is
  reachable." Otherwise there's nothing to see, and the app works the same
  online or off.
- **Signed out from elsewhere**, when a request gets 401 because an admin
  revoked this iPhone or removed the member: the app deletes the token, the
  local copy of the household's data and the queue, and returns to the welcome
  screen with "This iPhone was signed out. 2 changes that weren't sent yet are
  lost." A revoked phone keeps no lists.

## My account and the other screens

Mockups: `settings.html`. In the app the Items tab has a search field and no
heading. Each item reads "Market · Produce, also at 2 other stores". The
mockup's "Items tab, for comparison" and "+2" were mockup notes.

- **My account**, from the account circle:
  - a header with the member's name, an Admin badge for admins, and the server
    address;
  - List layout (Rows, Tiles) and Appearance (System, Light, Dark);
  - "Who can see my list": Open, Read-only, Hidden, with the product spec's
    note that hidden isn't encryption and that filed names reach the shared
    catalog;
  - "This iPhone": Add a device, Language, and Sign out;
  - "Household", for admins only: Members & devices.
- **Sign out** first tries to send the queue. If changes are still unsent, it
  asks before discarding them. If the server can't be reached, it offers "Sign
  out anyway", which deletes everything locally and says an admin should remove
  the device from the household's list **[Claude's call]**.
- **Add a device**: a QR code of the invite URL with "Scan with the new
  iPhone's Camera", who it signs in, that it works once, and when it expires.
  Then Share invite, Copy invite, the warning "Anyone with this invite can sign
  in as you until it's used or expires. Only send it to yourself.", and "Cancel
  invite", which revokes every pending invite for that member
  (`POST /v1/invites/revoke`).
- **Lists…**: the shared lists, with a name and one of the nine color tokens.
  Create, rename, recolor, archive. Archived lists sit in their own section
  with Restore. Not mocked up.
- **Stores & items…**: a Stores tab with stores in round-trip order and drag
  handles. A store opens to rename it, delete it, and add, rename, delete and
  drag its categories. Deleting says that its entries move to "Not filed yet".
  The Items tab lists the catalog, searchable: rename, change the usual store,
  set the category in each store, delete.
- **Members & devices**, for admins only: each member with their devices
  (name, last seen) or "Invited, not signed in yet". Tapping a member shows the
  Admin switch, their devices with Sign out, "Add a device for Sam…" and
  "Remove Sam…". "Invite a new member…" asks for a name and then shows the Add
  a device sheet for the new member. **[Claude's call]**: signing out another
  member's device here also revokes that member's pending invites, and the
  confirmation says so, because `API.md` notes that signing out a lost device
  doesn't revoke invites.
- Admin actions, invites and sign-out need a connection. Offline they say "Needs
  a connection to your server" instead of failing silently.
- Error copy for admin actions: `conflict` "Someone in the household already
  has that name.", `last_admin` "The household needs at least one admin."

## Language

- English and German, with every string translatable. More languages are added
  as translations, without code changes.
- The app follows the iPhone's language. iOS's per-app language setting
  (Settings > Apps > PocketLarder > Language) overrides it, so the app has no
  language setting of its own **[Claude's call, owner agreed]**.
- The Language row in My account shows the current language and opens the
  app's page in the Settings app.
- The documentation explains how to change the app's language. The owner asked
  for this explicitly.
- Server errors arrive as codes, so every message the app shows is translated
  in the app.
- **[Claude's call]**: German uses the informal "du".
- The owner and their partner check the German on the phone as part of each
  piece's checklist.

## Logo

Mockup: `logo.html` (option 2). Source: `logo.svg` (light) and `logo-dark.svg`
(dark).

- A jeans front pocket in white on teal: the small coin pocket with a stitched
  top hem and corner tacks, tucked behind the curved opening, which has one
  row of stitches. A checked-off list sticks out of the coin pocket. The owner
  chose it after a reference photo of a jeans front pocket.
- It's the home screen icon, in the light, dark and tinted styles iOS offers,
  and the welcome screen's logo **[Claude's call: the tinted variant is drawn
  from the same shape]**.
- The teal is the app's accent color.

## Under the hood

All **[Claude's call]**, within the product spec and `API.md`.

- **Local copy:** the last snapshot and the queue of unsent ops, as two files
  in the app's private storage. Each is written atomically, so a crash never
  leaves half a file, and the queue is written before a change shows on
  screen. Both are excluded from iCloud and device backups, so a restored
  phone can't replay old ops. A signed-out app holds neither.
- **What the screen shows** is the last snapshot with every unacknowledged op
  (queued, or in a request still waiting for its answer) re-applied in queue
  order. This is the client duty in `API.md`, and how "a sync never undoes a
  local change" holds. Applying an op locally mirrors the server's rules
  closely enough to look right until the next snapshot corrects it: filing
  links to an existing item with the same name ignoring case, deleting a store
  sends its entries to "Not filed yet", and so on.
- **Op ids:** a fresh random (version 4) UUID for every op, written in
  lowercase as `API.md` requires, and never reused, not even when an op is
  re-created after an edit. The server skips a repeated `op_id` without
  telling anyone, so a reused id silently loses a change. IDs of new entries,
  lists, stores, categories and items are lowercase random UUIDs too.
- **Sending:** at most 500 ops per request, in queue order, one request at a
  time. A 200 removes exactly the ops that were sent from the queue. Any other
  answer keeps them, unchanged, for the next attempt. A 401 signs out (see Sync
  feedback).
- **When it syncs:** on launch and on return to the foreground, about a second
  after a change, every minute while the app is open, and on pull-to-refresh.
  There's no background syncing.
- **Values are checked before they're queued:** text and names up to 100
  characters, quantity 32, note 200, counted the way the server counts them
  after the same cleaning, so a valid queue never gets 400 `invalid`.
- **Token:** in the Keychain, readable only while the phone is unlocked, this
  device only, never synced or backed up (from the product spec). It never
  appears in logs, error messages or screenshots.
- **Invite URLs** are secrets as well: never logged, kept only in memory while
  the sign-in or Add a device screen is open.
- **Accessibility:** the app works with Dynamic Type up to the largest
  accessibility sizes (tiles become a single column when text is large) and
  with VoiceOver. Every control, including ⇄ and the cross-off circle, has a
  tap area of at least 44 points and a spoken label. Rows offer "Cross off",
  "Move to store" and "Delete" as VoiceOver actions. List tags carry the list's
  name, so color is never the only signal. Animations respect Reduce Motion.
- iOS 27 or newer. SwiftUI, Swift 6 with strict concurrency checking.

## Documentation

- A README section for the app: what it needs (a PocketLarder server, iOS 27),
  building and installing it from source with Xcode, signing in with an invite,
  and changing the app's language in the iPhone's Settings.
- Each piece's pull request carries the owner's phone checklist.
- The Mac setup guide stays out of the repo (see How it gets made).

## Left to the builder

- The order and size of the pieces, which the plan decides.
- The tag color palette behind the nine color tokens, in light and dark, with
  readable contrast. Spacing, fonts, animations and haptics.
- The exact English and German copy wherever this document gives none, in the
  tone of the copy it does give.
- How the sample data for screenshots is loaded, and the file format of the
  local copy.
- Exact sync timing, within "about a second" and "every minute".
- How the Xcode project is laid out, within "editable without Xcode".

## Mockups

In `2026-10-30-pocketlarder-ios-mockups/`. Each file shows options. The chosen
one is named here.

- `welcome.html`: cards 1 and 2, the welcome screen in light and dark. Card 3
  was replaced by `enter-invite.html`.
- `enter-invite.html`: both cards, filled from a link and empty.
- `list-switcher.html`: option A, a switcher at the top and an add target at
  the bottom, as two controls.
- `switcher-label.html`: option 1, the tinted capsule, without the subtitle.
- `move-to-store.html`: option B, a move button on every row.
- `settings.html`: all four screens, with the Items wording above.
- `logo.html`: option 2, single stitching. The final artwork is `logo.svg` and
  `logo-dark.svg`.
