#!/usr/bin/env python3
"""The rules of the builder's hand-back hook. Run: python3 factory/tests/test_gate_hook.py"""

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

FACTORY = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory() as name:
    tmp = Path(name)
    (tmp / "factory/bin").mkdir(parents=True)
    shutil.copy(FACTORY / "bin/gate", tmp / "factory/bin/gate")
    shutil.copy(FACTORY / "config.json", tmp / "factory/config.json")
    # These checks count their runs, and fail while the file `fail` exists.
    (tmp / "factory/checks.sh").write_text("echo run >> runs\n[ ! -f fail ]\n")

    worktree = tmp / "worktree"
    worktree.mkdir()

    def commit():
        subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@example.invalid",
                        "commit", "--allow-empty", "-m", "c"], cwd=worktree, check=True, capture_output=True)

    subprocess.run(["git", "init"], cwd=worktree, check=True, capture_output=True)
    commit()

    folder = tmp / "factory/jobs/j"
    folder.mkdir(parents=True)
    (folder / "job.json").write_text(json.dumps({"worktree": str(worktree)}))
    agents = tmp / "session/subagents"
    agents.mkdir(parents=True)
    (agents / "agent-a.jsonl").write_text(json.dumps({"message": {"content": "Job: j. Job folder: x/."}}) + "\n")
    event = json.dumps({"transcript_path": str(tmp / "session.jsonl"), "agent_id": "a"})

    def hook():
        """The hook's exit code and how many times the checks have run so far."""
        res = subprocess.run([sys.executable, str(tmp / "factory/bin/gate"), "--hook"],
                             input=event, capture_output=True, text=True)
        runs = worktree / "runs"
        return res.returncode, len(runs.read_text().splitlines()) if runs.exists() else 0

    assert hook() == (0, 1), "passing checks let the hand-back through"
    (worktree / "fail").touch()
    assert hook() == (2, 2), "failing checks block the hand-back"
    assert hook() == (0, 2), "the same commit is nudged once, without running the checks again"
    commit()
    assert hook() == (2, 3), "a new commit is checked again"
    commit()
    (folder / "build.md").write_text("STATUS: BLOCKED\n\n## Blocked\nx\n")
    assert hook() == (0, 3), "a blocked build hands back without checks"

print("ok")
