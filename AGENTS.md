# PocketLarder

A self-hosted shopping list app: a household runs it on its own server to keep
shared shopping lists.

## Status

There is no application code yet, and the stack (language, framework, storage)
hasn't been chosen. The change that adds the first code must fill in Setup, Dev
server and Validation below. `factory/checks.sh` is protected from factory
jobs, so a human updates it to run the new validation commands.

## Setup

A fresh checkout needs no setup yet.

## Dev server

None yet. Once there is one, document how to start it on a given port: factory
agents each start their own on the port their prompt gives.

## Validation

`bash factory/checks.sh`. It runs no checks yet.

## Software factory

`/factory run` builds every open GitHub issue labeled `factory` through
intake → spec → build → gate → review → approve, one PR per issue. State is in
`factory/jobs/` (gitignored); `factory/bin/job` is its only writer. Checks:
`factory/checks.sh`. Dashboard: `cd factory && python3 -m http.server`, then
open http://localhost:8000/dashboard.html.
