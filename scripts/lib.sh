#!/bin/bash
# varde shared helpers. Sourced by the hook scripts.
#
# Rules every hook follows:
#   - Works on the bash 3.2 that ships with macOS. No jq, python, or node.
#   - No `set -e`. A hook that exits non-zero can block the user's prompt,
#     so every path ends in `exit 0`.
#   - Does nothing in a folder that has no .claude/varde.conf above it.
#   - Starts as few programs as it can. The prompt hook runs on every
#     prompt in every folder, and on macOS each grep, sed, or dirname costs
#     more than all the shell logic here put together. Prefer a bash
#     builtin wherever one does the job.

# Where per-session state is kept. Outside the project on purpose, so a
# fresh clone needs nothing and nothing here lands in git.
VARDE_DATA="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/varde-data}"

# Hook input arrives as one JSON object on stdin. Read it once.
INPUT="$(cat)"

# json_get FIELD
# Sets REPLY to the first top-level "FIELD": "value" found in INPUT, or to
# nothing. Quotes inside JSON strings are escaped (\"), so text typed into
# a prompt cannot fake a field.
json_get() {
  # The pattern has to sit in a variable for bash 3.2 to read it as a regex.
  local re="\"$1\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\""
  REPLY=""
  [[ $INPUT =~ $re ]] || return 0
  REPLY="${BASH_REMATCH[1]}"
  case "$REPLY" in *\\*) ;; *) return 0 ;; esac
  # Unescape \" \/ and \\ in that order. These also sit in variables:
  # bash 3.2 misreads a backslash-slash written straight into
  # ${var//pattern/replacement} and quietly replaces nothing.
  local bs='\' quote='"' slash='/'
  REPLY="${REPLY//"$bs$quote"/$quote}"
  REPLY="${REPLY//"$bs$slash"/$slash}"
  REPLY="${REPLY//"$bs$bs"/$bs}"
}

# file_mtime PATH
# Last-modified time in seconds since 1970. Prints 0 if the file is missing.
# macOS goes straight to its own stat by full path, so a GNU stat earlier
# on PATH can't answer instead. Elsewhere the GNU form is tried first,
# because the macOS form on Linux prints garbage.
file_mtime() {
  case "$OSTYPE" in
    darwin*) /usr/bin/stat -f %m "$1" 2>/dev/null || echo 0 ;;
    *)       stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0 ;;
  esac
}

# find_project_root DIR
# Walks up from DIR to the nearest folder holding .claude/varde.conf.
# Prints that folder, or nothing if there is none.
find_project_root() {
  local dir="$1"
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    if [ -f "$dir/.claude/varde.conf" ]; then
      printf '%s' "$dir"
      return 0
    fi
    # Step up to the parent. A path with no slash left has no parent.
    case "$dir" in */*) dir="${dir%/*}" ;; *) return 0 ;; esac
  done
  return 0
}

# conf_get FILE FIELD
# Reads one value from a field=value file. The file is committed and can
# arrive through a clone, so it is only ever read line by line, never run.
conf_get() {
  local line
  [ -r "$1" ] || return 0
  # The second test keeps a last line that has no newline after it.
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "$2="*) printf '%s\n' "${line#*=}"; return 0 ;;
    esac
  done < "$1"
  return 0
}

# is_number VALUE -> true when VALUE is a plain non-negative integer.
is_number() {
  case "$1" in ""|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

# The fields kept for each session.
state_reset() {
  S_transcript=""          # path to the session transcript
  S_started=0              # when this session began
  S_last_prompt=0          # when the latest prompt was sent
  S_prompts_since_status=0 # prompts since STATUS.md last changed
  S_prompts_since_nudge=0  # prompts since the last checkpoint nudge
  S_status_mtime_seen=0    # STATUS.md modified time at last check
  S_last_nudge=0           # when the last checkpoint nudge was printed
  S_ended=0                # when the session closed (0 = still open or crashed)
  S_reconcile_shown=0      # times the next session was told to reconcile
}

# state_load FILE
# Fills the S_ variables from FILE. Unknown fields are ignored and number
# fields that are not numbers fall back to 0.
state_load() {
  state_reset
  [ -f "$1" ] || return 0
  local field value
  while IFS='=' read -r field value; do
    case "$field" in
      transcript) S_transcript="$value" ;;
      started|last_prompt|prompts_since_status|prompts_since_nudge|status_mtime_seen|last_nudge|ended|reconcile_shown)
        is_number "$value" || value=0
        case "$field" in
          started)              S_started="$value" ;;
          last_prompt)          S_last_prompt="$value" ;;
          prompts_since_status) S_prompts_since_status="$value" ;;
          prompts_since_nudge)  S_prompts_since_nudge="$value" ;;
          status_mtime_seen)    S_status_mtime_seen="$value" ;;
          last_nudge)           S_last_nudge="$value" ;;
          ended)                S_ended="$value" ;;
          reconcile_shown)      S_reconcile_shown="$value" ;;
        esac
        ;;
    esac
  done < "$1"
  return 0
}

# state_save FILE
# Writes to a temp file first, then swaps it in, so a crash mid-write
# never leaves a half-written state file.
state_save() {
  local tmp="$1.tmp.$$"
  {
    echo "transcript=$S_transcript"
    echo "started=$S_started"
    echo "last_prompt=$S_last_prompt"
    echo "prompts_since_status=$S_prompts_since_status"
    echo "prompts_since_nudge=$S_prompts_since_nudge"
    echo "status_mtime_seen=$S_status_mtime_seen"
    echo "last_nudge=$S_last_nudge"
    echo "ended=$S_ended"
    echo "reconcile_shown=$S_reconcile_shown"
  } > "$tmp" 2>/dev/null && mv -f "$tmp" "$1" 2>/dev/null
  return 0
}

# varde_setup
# Parses the hook input and locates the project. Every hook calls this
# first. It exits the script quietly when there is nothing to do.
# Sets: SESSION_ID CWD TRANSCRIPT ROOT STATUS_FILE STATE_DIR STATE_FILE NOW
varde_setup() {
  # bash 5 knows the time by itself. The bash 3.2 on macOS has to ask date.
  NOW="${EPOCHSECONDS:-}"
  is_number "$NOW" || NOW="$(date +%s)"

  # Leave a trace that this hook ran, before any project check, so
  # /varde:doctor can answer "has this hook ever fired" from anywhere.
  local fired="$VARDE_DATA/fired"
  HOOK_NAME="${0##*/}"
  HOOK_NAME="${HOOK_NAME%.sh}"
  [ -d "$fired" ] || mkdir -p "$fired" 2>/dev/null
  [ -d "$fired" ] && echo "$NOW" 2>/dev/null > "$fired/$HOOK_NAME"

  json_get session_id;      SESSION_ID="$REPLY"
  json_get cwd;             CWD="$REPLY"
  json_get transcript_path; TRANSCRIPT="$REPLY"

  # Anything unexpected: do nothing.
  case "$SESSION_ID" in ""|*[!A-Za-z0-9_-]*) exit 0 ;; esac
  case "$CWD$TRANSCRIPT" in *'\u'*) exit 0 ;; esac
  [ -d "$CWD" ] || exit 0

  ROOT="$(find_project_root "$CWD")"
  [ -n "$ROOT" ] || exit 0

  local id
  id="$(conf_get "$ROOT/.claude/varde.conf" id)"
  case "$id" in ""|*[!A-Za-z0-9._-]*) exit 0 ;; esac

  STATUS_FILE="$ROOT/STATUS.md"
  STATE_DIR="$VARDE_DATA/projects/$id"
  STATE_FILE="$STATE_DIR/$SESSION_ID"

  [ -d "$STATE_DIR" ] || mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
}
