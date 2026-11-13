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
`gh run download <id> -n screenshots -D <dir>`. UI tests that fail run once more
at the end of the job; their second run's screenshots are in `rerun/`.

`-fixture household` (Debug builds only, `ios/PocketLarder/Fixtures/`) runs the app on sample data without a server, the Keychain or the real data folder, and the screenshot tests use it; `-fixture offline` is that account with every request failing as unreachable, so the app shows the offline badge and no data.

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

## Error messages

Every error says precisely what failed, so that an admin can troubleshoot a self-hosted install from the message alone: the host or step involved, and the real cause, such as DNS, a refused connection, a timeout, a certificate problem or an HTTP status. Never merge different causes into one message, and never advise a fix the cause doesn't call for. This wins over any copy in the plan or design. Tokens, invite codes and invite URLs still never appear in messages or logs. Known gaps are in #50.

## Versioning

The server and the app each have a MAJOR.MINOR.PATCH version, bumped by hand. The server's is `version` in `server/internal/larder/cli.go`, which `pocketlarder version` prints and `GET /v1/version` answers. The app's is `MARKETING_VERSION` in `ios/Config/PocketLarder.xcconfig`. The app's compatibility setting is `minimumServerVersion` and `supportedServerMajor` in `ios/PocketLarderKit/Sources/PocketLarderKit/Version.swift`: the app blocks a server below the minimum, or with a newer major than the supported one.

- **Server adds something the app will use** (a route, a field, a behaviour): the same PR bumps the server's MINOR and raises `minimumServerVersion` to it.
- **Breaking server change** (it changes or removes something older apps use): bump the server's MAJOR, and raise `supportedServerMajor` in the PR that adapts the app.
- **Server bug fix:** bump PATCH, at release time (see Release).
- **Database schema change alone:** needs no app change, because the server migrates its own data and refuses a database newer than itself.
- **Release:** bumping the app's version, and the server's version for fixes, is the owner's job at release time.

The contract test `serverIsCompatible` catches a minimum that the server of the same commit doesn't meet. A forgotten minimum can't be caught by a test, so code review checks every PR against these rules.

## Software factory

`/factory run` builds every open GitHub issue labeled `factory` through
intake → spec → build → gate → review → approve, one PR per issue. State is in
`factory/jobs/` (gitignored); `factory/bin/job` is its only writer. Checks:
`factory/checks.sh`. Dashboard: `cd factory && python3 -m http.server`, then
open http://localhost:8000/dashboard.html.
