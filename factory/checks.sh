#!/usr/bin/env bash
# The repo's checks. Exit 0 only when the branch is fit to review.
#
# The gate runs this script from the main checkout with the job's worktree as
# the working directory. Keep it fast, deterministic and non-interactive: no
# watch modes, no prompts, nothing that rewrites files. The one slow part is
# waiting for GitHub's Mac build on branches that touch ios/: FACTORY_SKIP_CI=1
# skips the wait, and FACTORY_CI_COMMIT names the commit whose build counts.
set -euo pipefail

cd server
unformatted=$(gofmt -l .)
if [ -n "$unformatted" ]; then echo "gofmt needed:"; echo "$unformatted"; exit 1; fi
go vet ./...
go test ./...
CGO_ENABLED=0 go build ./...
cd ..

changed=$(git diff --name-only "origin/main...HEAD")

# Kit and contract tests: any branch touching ios/ or server/, once the package
# exists. A server change has to keep working with the app. Docker runs as this
# user because files it writes as root can't be cleaned up without sudo.
if [ -f ios/PocketLarderKit/Package.swift ] && grep -qE '^(ios|server)/' <<<"$changed"; then
  tmp=$(mktemp -d)
  pid=
  cleanup() {
    if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; fi
    rm -rf "$tmp"
  }
  trap cleanup EXIT
  port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
  (cd server && CGO_ENABLED=0 go build -o "$tmp/pocketlarder" .)
  export POCKETLARDER_DATA_DIR="$tmp/data" POCKETLARDER_LISTEN="127.0.0.1:$port" POCKETLARDER_PUBLIC_URL="http://localhost:$port"
  invite=$("$tmp/pocketlarder" invite --new-admin Contract | tail -n 1)
  "$tmp/pocketlarder" serve >"$tmp/server.log" 2>&1 &
  pid=$!
  for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$port/v1/sync" && break; sleep 0.2; done
  docker run --rm --network host --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -e POCKETLARDER_TEST_SERVER="http://localhost:$port" -e POCKETLARDER_TEST_INVITE="$invite" \
    -v "$PWD/ios/PocketLarderKit:/pkg" -w /pkg swift:6.4.2-noble swift test
fi

# The app only builds on macOS: branches touching ios/ need a green `ios` run on GitHub.
if grep -q '^ios/' <<<"$changed" && [ -z "${FACTORY_SKIP_CI:-}" ]; then
  exec >&2 # The gate logs stdout before stderr and tails the log: failures here must come last.
  sha=${FACTORY_CI_COMMIT:-$(git rev-parse HEAD)}
  if ! gh api "repos/{owner}/{repo}/commits/$sha" --silent 2>/dev/null; then
    echo "$sha isn't on GitHub. Push the branch, then gate again."
    exit 1
  fi
  # By path, not name: .github/ is protected, so a branch can't answer with a workflow of its own.
  id=
  for _ in $(seq 60); do
    id=$(gh api "repos/{owner}/{repo}/actions/runs?head_sha=$sha" \
      -q '[.workflow_runs[] | select(.path == ".github/workflows/ios.yml")][0].id' || true)
    [ -n "$id" ] && break
    sleep 5
  done
  if [ -z "$id" ]; then
    echo "No ios workflow run for $sha after 5 minutes."
    exit 1
  fi
  if ! timeout 2700 gh run watch "$id" --exit-status --interval 30 >/dev/null; then
    echo "The ios workflow run $id failed or timed out:"
    gh run view "$id" --log-failed | tail -n 100 || true
    exit 1
  fi
  # A skipped job leaves the run green too.
  conclusion=$(gh run view "$id" --json jobs -q '.jobs[] | select(.name == "ios") | .conclusion')
  if [ "$conclusion" != success ]; then
    echo "The ios job of workflow run $id is '$conclusion', not success."
    exit 1
  fi
fi
