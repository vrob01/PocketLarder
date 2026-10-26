#!/usr/bin/env bash
# The repo's checks. Exit 0 only when the branch is fit to review.
#
# The gate runs this script from the main checkout with the job's worktree as
# the working directory. Keep it fast, deterministic and non-interactive: no
# watch modes, no prompts, nothing that rewrites files.
set -euo pipefail

# shortcut: PocketLarder has no application code yet, so there is nothing to check.
# Once a stack lands, replace this with its install, lint, typecheck, test and build commands.
echo "factory/checks.sh: no checks yet (no application code)."
