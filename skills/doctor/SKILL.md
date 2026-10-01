---
name: doctor
description: Check whether varde is working. Reports whether the plugin is installed, whether each hook has fired, what it knows about this project (marker, STATUS.md, log, git ignore rules), and this session's prompt counts against the reminder thresholds. Use when the user asks whether varde is running, why the status didn't save, why no reminder appeared, whether the hooks are firing, or to check the setup of a project. Also run it when a varde hook or command behaves unexpectedly.
argument-hint: "[folder]"
---

# Doctor

Hooks fail silently. A hook that never loaded, a session started before the install, or a threshold that wasn't set all look the same from the outside: nothing happens. This command makes the state visible.

Folder to check, if given: $ARGUMENTS

## 1. Run the check

```
bash "${CLAUDE_SKILL_DIR}/scripts/doctor.sh" "<folder>"
```

Leave the folder out to check the current directory. The script reads only and changes nothing.

## 2. Show the result

Print the script's output as it is, inside a code block. Every line is one check, marked `ok`, `warn`, `fail`, or `info`.

## 3. Explain what needs doing

For each `warn` or `fail`, one line: what it means and the fix. The common ones:

| Line | What it means | Fix |
|---|---|---|
| a hook has never run | Hooks load when a session starts. This session began before the plugin was installed or updated | Restart the session |
| this session has no counters yet | Same cause, seen from the project side | Restart the session |
| no `.claude/varde.conf` | This folder isn't a varde project | `/varde:new` adds the files without touching what's there |
| `STATUS.md` over the cap | It's being loaded every session at that size | Move finished items into the log, or run `/varde:wrap` |
| `log/` ignored but mode is standard, or the reverse | `.gitignore` and the marker disagree | Add or remove the `log/` line in `.gitignore` to match what the user wants |
| reminder thresholds show `default` when the user expected an override | The variables were not set when `claude` was started | Start it as `VARDE_NUDGE_PROMPTS=2 VARDE_NUDGE_MINUTES=0 claude` |

If everything is `ok` or `info`, say so in one line. Stop.
