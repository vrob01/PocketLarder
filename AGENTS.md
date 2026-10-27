# PocketLarder

A self-hosted shopping list app: a household runs it on its own server to keep
shared shopping lists.

## Status

The design is settled and the server is being built. Read these before touching
`server/`:

- Spec: `docs/superpowers/specs/2026-10-27-pocketlarder-design.md`
- Server plan: `docs/superpowers/plans/2026-10-27-pocketlarder-server.md`

The plan is built one task at a time, one factory issue per task, in order.
Each task builds on the merged PRs of the tasks before it. An issue that names a
plan task means exactly that task as the plan writes it: its files, interfaces,
tests and values. Where the plan and the spec disagree, the plan wins, because
it records decisions the spec left to the builder.

Layout: `server/` is the Go server (AGPL-3.0). `ios/` will hold the SwiftUI app
(MPL-2.0); its plan isn't written yet.

## Setup

Go 1.24 or newer on PATH. `server/go.mod` pins a newer toolchain, which `go`
downloads on first use. Then `cd server && go mod download`.

## Dev server

None yet. Task 6 of the server plan adds `pocketlarder serve` and documents here
how to start it on a given port: factory agents each start their own on the port
their prompt gives.

## Validation

`bash factory/checks.sh`. In `server/` it runs `gofmt -l`, `go vet ./...`,
`go test ./...` and a static build (`CGO_ENABLED=0 go build ./...`).

## Software factory

`/factory run` builds every open GitHub issue labeled `factory` through
intake → spec → build → gate → review → approve, one PR per issue. State is in
`factory/jobs/` (gitignored); `factory/bin/job` is its only writer. Checks:
`factory/checks.sh`. Dashboard: `cd factory && python3 -m http.server`, then
open http://localhost:8000/dashboard.html.
