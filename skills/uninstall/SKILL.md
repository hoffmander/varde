---
name: uninstall
description: Remove varde, either from one project or from this computer. Shows exactly what will be removed and what will be kept before doing anything. Never deletes CLAUDE.md, STATUS.md, the log, or private files. Run as /varde:uninstall.
argument-hint: "[project | plugin]"
disable-model-invocation: true
---

# Uninstall

Remove varde without losing any of the user's work. The status file, the log, and everything in `private/` belong to the user, so nothing here deletes them.

What the user asked for, if anything: $ARGUMENTS

## 1. Find out which one

There are two different things someone can mean:

| Choice | What it does |
|---|---|
| **This project** | varde stops running in one folder. The plugin stays installed for other projects |
| **The plugin** | varde is removed from this computer: both commands, all three hooks, and its session counters |

If the request above already says which, use that. Otherwise ask one question: "Remove varde from this project, or uninstall the plugin from this computer?"

## 2. Show the plan

Run the script without `--confirm`. It changes nothing and prints what would happen.

```
bash "${CLAUDE_SKILL_DIR}/scripts/uninstall.sh" project "<folder>"
bash "${CLAUDE_SKILL_DIR}/scripts/uninstall.sh" plugin
```

For a project, `<folder>` is the folder that holds `.claude/varde.conf`. Look in the current directory, then its parents.

Show the user the plan as two short lists: what will be removed, and what will be kept. Use the script's own lines. Then ask whether to go ahead.

## 3. Do it

Only after a yes. Run the same command with `--confirm` added at the end.

If any line starts with `failed`, show it and give the command to run by hand:

- `claude plugin uninstall varde@varde`
- `claude plugin marketplace remove varde`

## 4. Report and stop

- What was removed, one line each.
- What was kept.
- For the plugin: say that open sessions need a restart, and that the hooks keep running in this session until then.
- How to get it back: `/varde:new` inside a project folder adds the marker again without touching existing files. For the plugin, the install commands are in the README.

Stop.

## What stays behind, and why

- **`CLAUDE.md`, `STATUS.md`, `log/`, `private/`:** the user's work.
- **`.gitignore`:** removing lines from it could expose files that were being kept out of git.
- **The `@STATUS.md` line in `CLAUDE.md`:** it is a Claude Code feature, not part of the plugin, so the status still loads every session with varde gone. If the user wants that to stop too, offer to remove the `## Status` heading and the `@STATUS.md` line.
- **The session rules in `CLAUDE.md`:** they still tell Claude to keep the status and log current. Offer to remove the `## Session rules` section if the user wants varde's behavior gone completely.
