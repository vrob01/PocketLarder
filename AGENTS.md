# PocketLarder

A self-hosted shopping list app: a household runs it on its own server to keep
shared shopping lists.

## Status

The design is settled, the server is built and the iOS app is being built. Read
these before touching `server/` or `ios/`:

- Spec: `docs/superpowers/specs/2026-10-27-pocketlarder-design.md`
- Server plan: `docs/superpowers/plans/2026-10-27-pocketlarder-server.md`
- iOS design: `docs/superpowers/specs/2026-10-30-pocketlarder-ios-design.md`.
  It wins over the spec where they disagree about the app.
- iOS plan: `docs/superpowers/plans/2026-10-30-pocketlarder-ios.md`

Each plan is built one task at a time, one factory issue per task, in order.
Each task builds on the merged PRs of the tasks before it. An issue that names a
plan task means exactly that task as the plan writes it: its files, interfaces,
tests and values. Where the plan and the spec disagree, the plan wins, because
it records decisions the spec left to the builder.

Layout: `server/` is the Go server (AGPL-3.0). `ios/` holds the SwiftUI app
(MPL-2.0).

## Setup

Go 1.24 or newer on PATH. `server/go.mod` pins a newer toolchain, which `go`
downloads on first use. Then `cd server && go mod download`.

### iOS

`ios/PocketLarderKit/` is the Swift package (models, API client, sync; no UI),
`ios/PocketLarder/` the app, `ios/PocketLarderTests/` and
`ios/PocketLarderUITests/` its tests, `ios/Config/` the xcconfig and
`Info.plist`, `ios/PocketLarder.xcodeproj` the hand-written Xcode project (new
files in the app folders need no project edit). Docker, no Xcode needed, runs
the kit tests from the repo root:

```bash
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD/ios/PocketLarderKit:/pkg" -w /pkg swift:6.4.2-noble swift test
```

Xcode builds run only on GitHub: push, then wait for the `ios` run of your commit.
The screenshots of its UI tests are in the `screenshots` artifact:
`gh run download <id> -n screenshots -D <dir>`.

## Dev server

Factory agents each start their own server on the port their prompt gives. From
the repo root, with `<port>` filled in, in one shell:

```bash
cd server
export POCKETLARDER_DATA_DIR=$(mktemp -d) POCKETLARDER_LISTEN=127.0.0.1:<port> POCKETLARDER_PUBLIC_URL=http://localhost:<port>
go run . invite --new-admin Dev   # prints an invite for the admin Dev
go run . serve                    # runs until Ctrl-C or SIGTERM
```

`serve` and `invite` must share the data directory, so run `mktemp -d` only
once and keep the export for every later `go run . invite <name>`.

## Validation

`bash factory/checks.sh`. For `ios/` changes it also runs the kit tests and
waits for the green `ios` run of the commit (`FACTORY_SKIP_CI=1` skips the wait).
In `server/` it runs `gofmt -l`, `go vet ./...`,
`go test ./...` and a static build (`CGO_ENABLED=0 go build ./...`).

## Software factory

`/factory run` builds every open GitHub issue labeled `factory` through
intake → spec → build → gate → review → approve, one PR per issue. State is in
`factory/jobs/` (gitignored); `factory/bin/job` is its only writer. Checks:
`factory/checks.sh`. Dashboard: `cd factory && python3 -m http.server`, then
open http://localhost:8000/dashboard.html.
