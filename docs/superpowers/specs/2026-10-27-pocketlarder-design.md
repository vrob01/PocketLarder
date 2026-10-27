# PocketLarder design

Date: 2026-10-27. Status: approved by the owner on 2026-10-27.

This document comes out of an interview with the project owner. Statements without
a marker are the owner's decisions. **[Claude's call]** marks a choice made during
the interview that the owner heard but didn't make; **[guess, confirmed]** marks
a guess the owner accepted when it was played back. Anything under "Left to the
builder" is open.

## Intent

PocketLarder is a self-hosted, open-source shopping list app for one household.
It does one job, shopping lists, and leaves everything else to other tools, in the
spirit of "one job, one tool".

The household today uses KitchenOwl and likes it, but its development has stalled
and its iOS app falls short. PocketLarder takes KitchenOwl as inspiration and fixes
what bites this household:

1. **Items end up on the wrong list.** Each partner has a personal list and they
   share one or more lists. When someone remembers something in a hurry, they open
   the app and add it to whatever list happens to be open. Later, in the store,
   they're on a different list and the item is effectively hidden.
2. **Two naming styles collide.** One partner writes an umbrella item "spices"
   with a sub-item "burrito"; the other writes a top-level "burrito spice". Shared
   lists get messy.
3. **Offline breaks the list.** Every cross-off is an API call. Without a
   connection the app misbehaves, and items pop back onto the list once it
   reconnects.
4. **The order doesn't follow the store.** Categories group items, but the list
   order doesn't match the walk through the store, so you double back.
5. **The list view wastes space.** Tiles show too few items, the list view has
   lots of empty space, and icons are inconsistent (some items get one, others
   don't).

The household shops round trips of 3 to 5 stores, each with its own layout and
its own range of products.

## Goals

- Every list entry is shown under Store > Category, in the order you walk the
  store.
- Adding an item puts it in the right store and category automatically.
- You can't accidentally add to, or shop from, someone else's list.
- Both partners converge on the same item names without trying.
- Adding and crossing off work offline and sync without anything reappearing.
- A dense, modern iOS list.
- Self-hosting is a single container behind the owner's existing reverse proxy.

## Non-goals

- Recipes, meal planning, expenses, pantry or inventory tracking. Shopping lists only.
- A web interface. The server serves an API and nothing else.
- Importing from KitchenOwl. The household starts fresh.
- Sub-items or nested categories. Categories plus autocomplete cover it.
- Item icons.
- TLS or certificate handling in the server. The reverse proxy (Caddy, for the
  owner) does that.
- A separate database server. SQLite, inside the one container.
- Built-in passwords. Built-in passkeys, too (see Authentication for why).
- More than one household per server **[guess, confirmed]**. Other households run
  their own server.
- Push notifications **[Claude's call]**.
- Android, for now. It may come later as a second client of the same API, so the
  API must not assume iOS.

## Failure conditions

The owner named what would send the household back to KitchenOwl.

- **A security breach. This is a hard constraint.** Security is part of every
  design decision and is never traded away for simplicity, speed or convenience.
- **Hosting effort and interface complexity. These are soft constraints.** Keep
  both low by default: the owner's partner in particular will reject anything
  that feels complicated or offers too many choices. But they are expected to
  grow as the project grows, and the builder should not contort a solution to
  avoid needed effort or complexity when a real problem calls for it.
- **Items popping back** and over-complicated workflows count as bad UX.

## Concepts

- **Household**: everything on one server.
- **Member**: a person. Members are either admins or not. Every member can manage
  stores, categories and the catalog, and can see and edit every shared list
  **[Claude's call]**. Lists are separate mainly for organization: the partners shop
  separately and plan meals separately. Each member decides who else may see or edit
  their personal list (see "Personal list privacy").
- **Device**: a signed-in install of the app, belonging to one member.
- **List**: one personal list per member, created with the member, plus any number
  of shared lists. Typically there's one standing shared list and extra shared lists
  for events such as family gatherings. A shared list can be archived when it's no
  longer needed, which hides it from everyone's view, and restored later
  **[guess, confirmed]**. Each shared list has a name and a color used for its tag
  **[Claude's call]**. "Standing" and "event" aren't separate kinds.
- **Store**: a place you shop, such as a supermarket, a drugstore or a bakery. Stores
  have a household-wide order, which is the order of the round trip and is shown in
  "All" **[Claude's call]**.
- **Category**: belongs to exactly one store. A grocery store has "Dairy" and
  "Beverages", a drugstore has "Cleaning utensils" and "Makeup". Categories are
  freely reordered within their store to match its layout.
- **Item**: an entry in the household catalog, with a name, a **default store**,
  and a **placement** (a category) in each store that sells it. Names are unique
  within the household, ignoring case **[Claude's call]**.
- **Entry**: an item on a list, with an optional free-text quantity ("2", "500 g",
  no units system **[Claude's call]**), an optional short note, the store it's
  bought at (defaults to the item's default store and can be changed per entry),
  and whether it's still open or has been bought.
- **Unfiled entry**: an entry that has only free text and no catalog item yet.

## How it behaves

Mockups from the interview are in `2026-10-27-pocketlarder-mockups/`.
`store-view.html` shows the in-store view; layouts A and C are the ones chosen.
`add-flow.html` shows typing with suggestions and option B, "save now, file later",
which was chosen.

### My view

- The app opens on **My view**: the member's personal list plus every
  non-archived shared list, merged. Entries from shared lists carry a small tag with
  the list's name and color. Entries with no tag are the member's own.
- Other members' personal lists are reachable only by deliberately switching to
  them. The app never lands on them: it returns to My view whenever it comes back
  to the foreground after more than 5 minutes in the background, and on every launch
  **[Claude's call]**.
- Store chips along the top filter to one store, for when you're standing in it.
  "All" shows every store in round-trip order.
- Within a store, entries are grouped by category in that store's category order.
  Within a category, alphabetical by name **[Claude's call]**.
- Each member chooses one of two layouts: **dense rows** (mockup A) or **compact
  two-column tiles** (mockup C). No icons in either.
- Appearance follows the iPhone's light/dark setting by default, with a per-device
  override to always light or always dark. Dark theme is required.

### Personal list privacy

Each member can protect their own personal list. There are three settings:

- **Open** (the default): others can see it and edit it.
- **Read-only**: others can see it but can't add, change or cross off anything.
- **Hidden**: others can't see it at all. It isn't in their list switcher or the
  add bar's list picker, and it never syncs to their devices.

**[Claude's call]** It's one three-way setting rather than two independent switches.
"Hidden but writable" would mean adding to a list you can't see, which is confusing,
so hidden includes read-only.

- Admins get no exception in the app. A hidden list is hidden from them too.
- Hidden isn't encryption. Whoever runs the server can read the database, and the
  setting's description in the app says so **[Claude's call]**.
- The catalog stays shared by the whole household. Filing an entry from a hidden
  list puts the item's name into the catalog, where others see it in suggestions,
  though not whose list it's on. To keep something completely private, leave it
  unfiled. The setting's description says this too **[Claude's call]**.

### Adding

- The add bar is always visible and always shows which list a new entry will land on.
  In My view that's the member's personal list. Tapping it picks another list. The
  choice holds while you're adding several items and resets to the personal list
  under the same rule as returning to My view **[Claude's call]**.
- Typing searches the household catalog and shows matches first, with each match's
  store and category, so both partners pick the same item instead of creating a new
  one.
- Picking a match adds an entry under the item's default store and its category
  there. If the item is already open on that list, the app shows the existing entry
  instead of adding a duplicate **[Claude's call]**.
- **No match: save now, file later.** Pressing return saves an unfiled entry right
  away. It needs no store, no category and no extra taps. Unfiled entries appear in
  a "Not filed yet" section at the top of every store, so they can't be missed.
- Unfiled entries never enter the catalog and never appear in suggestions. This is
  deliberate: one-off purchases can stay unfiled for good without cluttering
  search.
- **Filing** an unfiled entry means picking a store and a category. That creates
  the catalog item, with the chosen store as its default. If a catalog item with
  the same name already exists, filing links the entry to it instead of creating a
  duplicate **[Claude's call]**.

### Shopping

- Tapping an entry's circle (rows) or the tile (tiles) crosses it off. It moves to
  that list's **recently bought** section, newest first, where one tap puts it back
  on the list.
- Moving an entry to another store: swipe on the entry and choose "Move to store"
  **[Claude's call]**. If the item has no placement in that store yet, the app asks
  for the category once and remembers it as a new placement.
- Quantity and note are edited by tapping the entry **[Claude's call]**.

### Settings, for every member

- List layout: rows or tiles.
- Appearance: system, light or dark.
- Personal list privacy: open, read-only or hidden.
- Stores and categories: add, rename, delete, and drag to reorder. Catalog items
  can be renamed, re-placed or deleted here too.
- Server connection: the server address, who you're signed in as, sign out, and
  "Add a device", which creates an invite for your own account.

Layout, appearance and personal list privacy are the only preferences. Don't add
more unless a real problem calls for one.

### Admin area, visible to admins only

- Invite a new member.
- Make a member an admin, or remove admin.
- See each member's devices (name, last seen) and revoke any of them.
- Remove a member. This revokes all their devices and, after confirmation, deletes
  their personal list **[Claude's call]**.

## Authentication

There are two ways in: **invite pairing** (built in, no passwords) and **OIDC**.
The server never stores a password or any other secret a user could reuse
elsewhere.

**Why not built-in passkeys.** A native iOS app can only use passkeys for domains
written into the app when it's built (Associated Domains, which also requires the
paid developer program). A self-hosted app can't know its server's domain ahead of
time. The workarounds are a login web page served by PocketLarder, which brings
back a web interface, or one project-owned domain shared by every install, which
ties self-hosters to a domain the project has to keep alive. Both were rejected.
Members who want passkeys get them through their OIDC provider. Pocket ID, for
example, only does passkeys.

### Invite pairing

- An invite is single-use, high-entropy and short-lived (24 hours
  **[Claude's call]**). It's bound either to a new member being invited or to an
  existing member adding a device.
- It's shown as a QR code (a `pocketlarder://` URL) plus a copyable text code, and
  both carry the server address and the secret **[Claude's call]**. Scanning or
  pasting it fills in the server address and signs the device in, all in one step.
  Universal links aren't used because they need the paid developer program.
- Redeeming an invite gives the device a **device token**: random, at least 256
  bits, stored on the phone in the Keychain as this-device-only (not synced, not in
  backups) **[Claude's call]**. The server stores only a hash of each token and each
  invite.
- Device tokens don't expire by time. They end when the user signs out (the app
  deletes the token and the server revokes it), when an admin revokes them, or
  when the member is removed.
- Getting back in after a sign-out is a new invite for the *existing* member, so
  lists and data stay. It can come from another signed-in device of the same member
  ("Add a device"), from an admin, or from the server's command line.

### OIDC

- Optional. It's enabled by configuring the server with an issuer and client ID.
- The app signs in with the provider as a public native client using authorization
  code + PKCE in `ASWebAuthenticationSession`. The server verifies the resulting ID
  token (signature against the issuer's published keys, issuer, audience, expiry)
  and exchanges it for a device token. From then on it behaves like an invite
  pairing **[Claude's call]**.
- An OIDC identity can only sign in once it's linked to a member. Linking happens
  by redeeming an invite through OIDC sign-in. A provider login never creates a
  member automatically **[Claude's call]**.

### Bootstrap

On an empty database, `docker exec pocketlarder pocketlarder invite --new-admin <name>`
creates the first admin and prints an invite. `pocketlarder invite <member>` prints a
device invite for an existing member, which is the recovery path when nobody is
signed in anywhere. Shell access to the server is the root of trust
**[Claude's call]**.

## Server

- Go. A single static binary in a single container image that contains nothing else
  **[Claude's call, owner agreed]**.
- SQLite in a file on a mounted volume, using a pure-Go driver so the binary stays
  static.
- It speaks plain HTTP and expects to run behind a TLS-terminating reverse proxy.
- It serves a versioned JSON API only: no HTML, no static files, no CORS headers.
  The API is documented in the repo (an OpenAPI file or similar) so a future Android
  client can be built from it **[Claude's call]**.
- Configured through a few environment variables: data directory, listen address,
  the public URL used inside invites, and the optional OIDC issuer and client ID
  **[Claude's call]**.
- Database schema upgrades run automatically at startup **[Claude's call]**.
- `pocketlarder backup <path>` makes a consistent copy of the database while the
  server is running **[Claude's call]**. Scheduling and storing backups is left to
  the host's own tools.
- The repo ships a `Dockerfile`, an example `compose.yaml` and an example Caddy
  site block. Hosting means: build or pull the image, mount a volume, set the
  environment variables, add the Caddy block **[Claude's call]**.

### Sync and offline

- The app keeps a full local copy of the household's data (lists, entries, stores,
  categories, catalog) and works fully offline.
- Every change is recorded locally first and queued. The queue is sent when there's
  a connection. Changes carry client-generated IDs, so sending one twice is harmless.
- **Hard requirement: a sync never undoes a local change.** An entry crossed off
  offline stays crossed off, and only reappears if someone re-adds it. Until the
  server has acknowledged a local change, the app applies it on top of whatever the
  server sends.
- When two members change the same thing, the change that reaches the server last
  wins **[Claude's call]**.
- The app syncs when opened, on pull-to-refresh, and every so often while it's in
  the foreground **[Claude's call]**. There's no push and no persistent connection.

## Security requirements

These apply to every part and every change. They're the hard constraint from
"Failure conditions".

- No reusable secrets at rest on the server: tokens and invites are stored only as
  hashes. Comparisons run in constant time.
- Don't hand-roll crypto or JWT/OIDC verification. Use the standard library and
  well-maintained, widely used libraries. Keep the dependency list short and
  justify each entry.
- Every API request except invite redemption and OIDC exchange requires a valid
  device token. Unauthenticated endpoints are rate-limited.
- Validate every input at the API boundary: types, lengths, ownership. Limit
  request sizes.
- The server enforces list privacy, not the app. It rejects any read or write a
  list's privacy setting forbids, and never sends a hidden list's entries (including
  recently bought) to another member's device. When a list becomes hidden, the
  next sync removes it from other members' devices.
- Tokens, invites and ID tokens never appear in logs or error messages.
- The container runs as non-root with a read-only root filesystem. The only
  writable path is the data volume.
- The app refuses a server address that isn't `https://`, except `localhost` for
  development.
- Changes touching auth, sync or the API get the factory's security review.

## iOS app

- Native SwiftUI, targeting iOS 27 **[Claude's call, owner agreed]**. Both members
  are on iOS 27.
- Built on the owner's MacBook Air (Apple silicon). That Mac has no developer tools
  yet, so the plan must include a step-by-step setup guide written for someone who
  has never built an Apple app: Xcode, signing with a free Apple ID, and installing
  on both phones.
- To start, distribution uses a free Apple ID: Xcode installs the app on both
  phones, and it has to be reinstalled from the Mac every 7 days. The paid developer
  program ($99/year, required for TestFlight and the App Store) comes later. Nothing
  in this design may depend on paid-only capabilities such as Associated Domains or
  push.

## Repository, testing and licensing

- One repo: `server/` (Go), `ios/` (Xcode project), `docs/` **[Claude's call]**.
- **Licenses:** AGPL-3.0 for the server, MPL-2.0 for the iOS app. The goal is that
  anyone may host PocketLarder, including commercially, but nobody can turn it into
  a closed-source product. The current root `LICENSE` is GPL-3.0 and must be replaced
  by per-directory licenses plus a root note.
- **Server checks:** formatting, `go vet` and `go test ./...`, all runnable on Linux.
  The factory machine has Go 1.24.4 and Docker, and its user is in the `docker`
  group, so factory jobs can build and smoke-test the container image. The checks
  themselves don't need Docker.
  The first code change must fill in Setup, Dev server and Validation in
  `AGENTS.md`. `factory/checks.sh` is protected from factory jobs, so the owner
  updates it by hand to run these.
- **iOS checks:** `xcodebuild` build and test on GitHub Actions macOS runners, so
  factory changes to the app are checked even though the factory machine runs Linux
  **[Claude's call]**. The repo is public from the start, which makes these runs
  free. That was the owner's decision.

## Left to the builder

- API shape, endpoints and the exact sync protocol, within the rules above.
- The SQL schema, and the app's local storage technology.
- Search matching beyond case-insensitive prefix and substring (typo tolerance, for
  example).
- What happens to placements and entries when a store or category is deleted, as
  long as no entry is ever silently lost (orphans become unfiled, for example).
- How often the app syncs in the foreground, the rate limit values, the size
  limits, and how many recently bought entries to keep.
- Visual details beyond the mockups: spacing, the tag color palette, animations.
- Build order. A sensible one: server core with invite auth and sync, then the iOS
  app, then OIDC, then CI.

## Later, not now

- The paid Apple developer program, TestFlight and App Store release.
- An Android client.
- Quick capture from outside the app (widgets, Siri, Shortcuts).
