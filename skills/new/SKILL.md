---
name: new
description: Set up a project folder that Claude Code can pick up from in any later session. Creates CLAUDE.md with the goals, a short STATUS.md, a dated log, a .gitignore, and a first git commit. Works for any kind of project, code or not (an app, a presentation, paperwork, a trip, a build). Use when the user wants to start a new project, set up or organize a project folder, keep track of a project across sessions, or add varde to a folder that already exists, even if they never say "varde". Not for generating framework code such as a new Next.js or Rails app.
argument-hint: "[project name]"
---

# New project

Set up a folder that any later session can pick up from cold. The folder starts blank on purpose: every project grows a different shape, so varde adds the files that track the work and nothing else.

Project name, if given: $ARGUMENTS

## 1. Interview

Three questions, asked in plain chat, one per message. Wait for each answer before asking the next.

1. **Name and description.** What's the project called, and what is it?
2. **Goals.** What are you trying to get done? Two to five is plenty.
3. **Done.** How will you know it's finished?

Why one at a time: a list of questions reads like a form, and people skim forms. One question gets a real answer. So each message is the question and nothing else. No preamble, no recap, no preview of what comes next, no note about where the folder will go.

Skip a question the user already answered, whether in the project name above or in an earlier reply.

Write the answers into the files in the user's own words. Tidy the grammar, but add nothing they didn't say. These files are what every future session reads first, so an invented goal becomes a false instruction. If an answer is still missing after one ask, write `Not decided yet.` and move on.

## 2. Choose the mode

Do not ask. Decide from what the user said:

| Mode | When | What git sees |
|---|---|---|
| **Standard** | The default | `private/` is ignored. The log is committed |
| **Sensitive** | The user says so, or the name or description is plainly medical, legal, financial, or work-confidential | `private/` and the log are both ignored |

When unsure, choose sensitive. A log kept off GitHub by mistake costs one line in `.gitignore` to fix. A medical detail pushed by mistake can't be taken back.

## 3. Pick the folder

- **New project:** `<current directory>/<name in lowercase-kebab-case>`.
- **Existing folder:** if the user asked to add varde to a folder that exists, or the current directory is the project, use it as is. Do not rename it.

Say the full path in one line before creating anything. If the current directory is the user's home folder, ask where projects should live first, since a project folder loose in the home folder is rarely what anyone wants.

## 4. Create the files

```
bash "${CLAUDE_SKILL_DIR}/scripts/scaffold.sh" "<folder>" <yes|no> "<project name>"
```

The second argument is `yes` for sensitive, `no` for standard.

The script never overwrites or edits a file that already exists, which is what makes it safe to run on a folder full of someone's work. It prints one line per item (`created`, `skipped`, or `note`), then a `mode` line.

## 5. Fill in CLAUDE.md

Only if the script printed `created CLAUDE.md`. Replace these placeholders in `<folder>/CLAUDE.md`:

- `{{PURPOSE}}`: one or two sentences.
- `{{GOALS}}`: a bullet list.
- `{{DONE}}`: one to three bullets.

Leave the rest of the file as it is. The `@STATUS.md` line at the bottom is what loads the status at the start of every session, so it has to stay.

If the user named any first steps, put them under `## Next` in `STATUS.md`.

## 6. Handle notes

Do this before committing. Each `note` line is something the script found but would not change on its own, because the file belongs to the user. Tell them what is missing, offer the fix, and make it only after a yes.

| Note | What to offer |
|---|---|
| `CLAUDE.md has no @STATUS.md line` | Add a `## Status` heading with `@STATUS.md` under it, at the end of their `CLAUDE.md` |
| `.gitignore does not ignore <entry>` | Add that line to the end of their `.gitignore` |
| `.gitignore does not limit git to varde's files` | Append the contents of `${CLAUDE_SKILL_DIR}/assets/gitignore-allowlist` to their `.gitignore`. Explain it: the folder already holds files that one `git add` would pick up, and this makes git ignore everything except varde's files |
| `<N> untracked items in this repository are not ignored` | The folder was already a repository, so varde left its rules alone. Give the count and ask whether those files belong in `private/` or need their own ignore lines. Do not move files |
| `git is limited to varde's files` | Nothing to fix. Say it in one line, and that a file gets tracked by adding a `!/name` line to `.gitignore` |

Hold the commit until `private/` is ignored, and in a sensitive project `log/` too. If the user declines the `.gitignore` fix, skip the commit and say why.

## 7. First commit

```
bash "${CLAUDE_SKILL_DIR}/scripts/commit.sh" "<folder>" "Set up <project name> with varde."
```

The script commits only the files varde created. Everything else in the folder stays as it was, staged or not. It never adds a remote and never pushes.

If the script printed `skipped git init (already a repository)` in step 4, ask before running the commit, since this would add to a history the user already owns.

## 8. Report and stop

- What was created and what was skipped, one line each.
- The mode and what it means, in one line, taken from the `mode` line the script printed. If you chose sensitive on your own, say what in the description made you choose it, so the user can correct you.
- How to switch modes: add `log/` to `.gitignore` to keep the log local, or remove that line to commit it.
- The command that opens the project:

```
cd "<folder>" && claude
```

Then stop. This session is not running inside the new folder, so the status file and the hooks only take effect in a session started there. Starting on the project's goals here would do the work in the wrong place.
