# Changelog

## 0.4.1

- Listing icon at `.claude-plugin/icon.png` and a new header image, both with embedded metadata removed.
- `scripts/lib.sh` parses hook input without `eval`, so the directory's security scan has nothing to hold.

## 0.4.0

- `/varde:uninstall` also removes Claude Code's cached copies of the plugin.
- The scaffolded `CLAUDE.md` tells Claude to keep project state in `STATUS.md` and the log, not in memory.
- Log entries gain an optional `Tried:` line for approaches that were dropped, and why.
- First public release on GitHub.

## 0.3.0

- `/varde:doctor` reports whether the plugin is installed, whether each hook has fired, the state of the project files, and this session's prompt counts against the thresholds.
- The session start hook prints an index of every `Decided:` line in the log, newest first, capped by `VARDE_INDEX_LINES` (default 15). It is also printed after compaction.
- Text read back from the log or an old conversation is marked as a record, not instructions, in the hook output, the `CLAUDE.md` template, and the wrap skill.
- Each hook leaves a trace of when it last ran, so the doctor can tell a hook that never loaded from one with nothing to say.

## 0.2.0

First public version.

- `/varde:new` sets up a project folder with three questions, asked one at a time.
- `/varde:wrap` saves the status, adds to the log, and offers a commit.
- `/varde:uninstall` removes varde from one project or from the computer, and shows the plan first.
- Three hooks: a session-start report, a save reminder, and a session-end record.
- Two modes, chosen without asking: standard commits the log, sensitive keeps it on the machine.
- `private/` is ignored by git in every project.
- A sensitive project added to a folder that already holds files limits git to varde's own files.
- Decisions are written to the log when they are made, not at the end of the session.
- `tests/run.sh` checks the scripts without needing a Claude session.
