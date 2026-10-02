# varde

**A Claude Code plugin that sets up a blank project folder and keeps a short status file current between sessions.**

![Varde: a stack of colored stones in a park, with a tower behind it](github-header.png)

A varde is a stone cairn, the kind Norse travelers stacked along trails and coastlines to mark the way. Each session adds a stone, and the stack shows the next session where to go.

It works for any kind of project, code or not: an app, a presentation, insurance paperwork, a trip, a truck build.

```
> /varde:new

  What's the project called, and what is it?
> Camp Kitchen. A slide-out kitchen for the truck bed.

  What are you trying to get done? Two to five goals is plenty.
> Design the drawer, buy the slides, build it.

  How will you know it's finished?
> I cook a meal on it at camp.

  Created CLAUDE.md, STATUS.md, log/2026-09.md, .gitignore, private/
  Committed to main. cd camp-kitchen && claude
```

Three days later, in a new session, Claude already knows where you left off.

## Install

Needs macOS, git, and Claude Code. Nothing else: no Node, Python, database, or API key. Tested on Claude Code 2.1.284.

```
claude plugin marketplace add hoffmander/varde
claude plugin install varde@varde
```

Then start a new session and run `/varde:new`.

## What you get

```
camp-kitchen/
  CLAUDE.md            what the project is, its goals, and the session rules
  STATUS.md            where things stand, under 60 lines
  log/2026-09.md       dated history, one file per month: Did, Decided, Tried, Next
  private/             ignored by git, for anything that stays on your machine
  .claude/varde.conf   marks the folder as a varde project
  .gitignore
```

No other folders. Every project grows a different shape, so varde adds the files that track the work and leaves the rest to you.

`STATUS.md` has five headings and nothing else:

```markdown
# Status

## Last session (2026-09-29)
- Measured the truck bed: 60 in by 41 in between the wheel wells.
- Chose 500 lb locking slides, because the stove and water add up to 140 lb.

## Now
- Drawing the drawer box.

## Blocked
- Slides are backordered until 2026-10-12.

## Next
- Buy plywood.

## Later
- Fold-out side table (idea, not final).
```

## Commands

| Command | What it does |
|---|---|
| `/varde:new` | Asks three questions, one at a time, then creates the files and makes the first commit. Run it inside a folder that already exists and it adds only what is missing |
| `/varde:wrap` | Rewrites `STATUS.md`, adds a dated entry to the log, and offers a commit |
| `/varde:doctor` | Checks that the plugin is installed, the hooks are firing, the project files are in order, and shows this session's prompt counts against the reminder thresholds |
| `/varde:uninstall` | Removes varde from one project or from your computer. Shows the plan first |

`/varde:wrap` is optional. Claude saves the status as you work, and wrap is there for when you want a clean close and a commit.

## How the status stays current

| Part | How |
|---|---|
| **Loading** | `CLAUDE.md` ends with `@STATUS.md`, so Claude Code loads the status at the start of every session. This works on any computer, with or without the plugin |
| **Saving** | Claude updates `STATUS.md` as work finishes, and writes each decision to the log when it's made. After 8 prompts and 20 minutes with no status change, a hook reminds it to save during the turn it's already taking |
| **Recovery** | If a session ends without saving (closed window, crash, forgot), the next session reads the end of the old conversation and brings the status up to date before starting anything new |
| **History** | Finished items leave `STATUS.md` and go into `log/`. The log itself is never loaded. What is loaded, at session start and after compaction, is a short index: every `Decided:` line from the log, newest first, up to 15 of them. That is enough to answer "why did we go with X" without reading the log, and the rest is one grep away |

### The hooks

| Hook | Script | What it does |
|---|---|---|
| SessionStart | `scripts/session-start.sh` | Tells Claude how long ago the last session was, whether it went unsaved, and whether `STATUS.md` is over 60 lines |
| UserPromptSubmit | `scripts/prompt-checkpoint.sh` | Counts prompts and prints the save reminder |
| SessionEnd | `scripts/session-end.sh` | Records that the session closed |

- **They do nothing outside varde projects.** Each one exits right away in a folder with no `.claude/varde.conf`.
- **They are plain bash**, written for the bash 3.2 that ships with macOS, with comments on every step.
- **They never change your files.** They don't write to the project and they don't run any git command that changes something. Only Claude edits `STATUS.md` and the log, in the open, where you can see it.
- **Session counters live outside the project**, in `~/.claude/plugins/data/`. Nothing about your sessions lands in the repo.
- **What they read back is marked as a record.** The log index and the recovery note both tell Claude the text is a record of what happened, not instructions to act on, so nothing written into a log entry or an old conversation can steer a later session.

## What goes to git

varde runs `git init` and makes one commit. It never adds a remote and never pushes. What that commit and later ones can include depends on the mode.

The mode is chosen for you. It's standard unless you say the project is sensitive, or the description is plainly medical, legal, financial, or work-confidential. When it isn't clear, varde picks sensitive and tells you why.

| | Standard | Sensitive |
|---|---|---|
| `private/` | ignored | ignored |
| `log/` | committed | ignored |
| `STATUS.md`, `CLAUDE.md` | committed | committed |
| Files already in the folder | tracked as usual | ignored, unless the folder was already a git repository |

- **Standard** keeps your history with the project, so it survives a dead laptop and shows up on another computer.
- **Sensitive** keeps the log on the machine it was written on.
- **`STATUS.md` is committed in both modes.** varde tells Claude to keep account numbers, ID numbers, and personal details out of it. That is an instruction, not a lock, so read `STATUS.md` before you push a sensitive project.
- **To switch later,** add or remove the `log/` line in `.gitignore`.

## Uninstall

```
/varde:uninstall
```

It asks whether you mean this project or the whole plugin, shows what would be removed and what would be kept, and waits for a yes.

| | From one project | From your computer |
|---|---|---|
| Removes | `.claude/varde.conf` and that project's session counters | The plugin, its marketplace entry, its cached copies, and all session counters |
| Keeps | `CLAUDE.md`, `STATUS.md`, `log/`, `private/`, `.gitignore` | Every project folder and everything in it |

Your status file keeps loading after an uninstall, because the `@STATUS.md` line is a Claude Code feature and not part of the plugin.

To uninstall by hand:

```
claude plugin uninstall varde@varde
claude plugin marketplace remove varde
```

## How it compares

varde is small on purpose. If you want more than a status file and a log, these are worth a look. Descriptions are from each project's README as of 2026-09-29.

| | What it is | Needs |
|---|---|---|
| **Claude Code `/resume` and `--continue`** | Restores a whole past conversation. Built in | Nothing. Conversations are deleted after 30 days by default, and they stay on one computer |
| **Claude Code auto memory** | Notes Claude saves for itself, outside the project folder. Built in | Nothing. Stays on one computer |
| **[claude-mem](https://github.com/thedotmack/claude-mem)** | A second model records what the agent does with its tools, stores it in a database, and makes it searchable in later sessions | Node, Bun, uv, and a background service |
| **[planning-with-files](https://github.com/OthmanAdi/planning-with-files)** | A plan, findings, and progress file for the current task, fed back in on every prompt and before tool calls | A shell. Python is optional |
| **varde** | One status file and a dated log per project, in the project folder, that you can read and edit | Nothing |

Where varde is the wrong choice:

- **You only work in code, on one computer, and come back within a month.** The built-in `/resume` and auto memory already cover that.
- **You want search across everything you've ever done.** varde has no search. It has one short file and a log you can grep.
- **You want the tool to enforce a plan.** varde reminds. It doesn't block.

Where it fits:

- **Projects that aren't code**, or aren't only code.
- **Projects you leave for weeks**, where the old conversation is gone but the status file isn't.
- **Projects that move between computers** through git.
- **Folders that hold private documents.**

## Questions

**Does it work for code projects?**
Yes. The `.gitignore` covers common build folders, and running `/varde:new` inside an existing repository adds varde's files without touching yours.

**Does it work with a `CLAUDE.md` I already have?**
varde won't edit it. It offers to add the `@STATUS.md` line and does so only if you say yes.

**How is this different from Claude Code's own memory?**
Memory is stored on your computer, outside the project. It doesn't travel with the folder or go to GitHub. varde keeps the project's state in plain files inside the project, where you can read, edit, and commit them. The scaffolded `CLAUDE.md` tells Claude to keep project state in those files rather than in memory, so there is one copy, not two.

**What does it cost in tokens?**
About 400 tokens per session for the three command descriptions, plus the length of your `STATUS.md`. The hooks add nothing unless they have something to report.

**Does anything leave my computer?**
No. varde makes no network requests. It reads and writes files in your project and in `~/.claude/plugins/data/`.

**Why didn't it save, or remind me?**
Run `/varde:doctor`. It shows whether each hook has fired, this session's prompt count, and the thresholds in effect. The usual cause is a session that was started before the plugin was installed.

**Can I change the save reminder?**
Yes, with the environment variables below.

## Settings

Set these before starting Claude Code.

| Variable | Default | Meaning |
|---|---|---|
| `VARDE_NUDGE_PROMPTS` | 8 | Prompts before a save reminder |
| `VARDE_NUDGE_MINUTES` | 20 | Minutes before a save reminder |
| `VARDE_IDLE_SECONDS` | 600 | Quiet time before a session counts as over |
| `VARDE_MIN_PROMPTS` | 3 | Unsaved prompts that trigger recovery |
| `VARDE_INDEX_LINES` | 15 | Decisions shown from the log at session start. `0` turns the index off |

Example: `VARDE_NUDGE_PROMPTS=2 VARDE_NUDGE_MINUTES=0 claude`

## Working on varde

```
git clone https://github.com/hoffmander/varde
bash varde/tests/run.sh                # checks the scripts, no Claude session needed
claude --plugin-dir ./varde            # try your copy for one session
```

An installed plugin is a copy. To get a change into it, raise `version` in `.claude-plugin/plugin.json`, then run `claude plugin marketplace update varde` and `claude plugin update varde@varde`.

## Not in this version

- Linux and Windows. The scripts are written to be portable, but only macOS is tested.
- A command that switches a project between standard and sensitive.
- Creating a GitHub repository or pushing.

## License

MIT
