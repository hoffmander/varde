#!/bin/bash
# varde doctor. Reports whether varde is installed, whether its hooks have
# fired, and what it knows about the current project and session.
#
# Usage:  bash doctor.sh [folder]        (default: the current directory)
#
# Reads only. Changes nothing. Always exits 0.
#
# Each line is one check:
#   ok      as expected
#   warn    works, but something is off
#   fail    varde is not doing its job here
#   info    a fact, nothing to fix

TARGET="${1:-$PWD}"
PLUGIN_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LIB="$PLUGIN_ROOT/scripts/lib.sh"
NOW="$(date +%s)"
STATUS_CAP=60

# The hooks' helpers (find_project_root, conf_get, file_mtime, state_load).
# lib.sh reads hook input from stdin, so feed it nothing.
if [ -f "$LIB" ]; then
  . "$LIB" < /dev/null
else
  echo "fail    scripts/lib.sh is missing from $PLUGIN_ROOT"
  exit 0
fi

# ago SECONDS -> "3 minutes ago"
ago() {
  local s="$1"
  if   [ "$s" -lt 60 ];    then echo "${s}s ago"
  elif [ "$s" -lt 3600 ];  then echo "$(( s / 60 )) min ago"
  elif [ "$s" -lt 86400 ]; then echo "$(( s / 3600 )) h ago"
  else                          echo "$(( s / 86400 )) days ago"
  fi
}

# --- Plugin ---------------------------------------------------------------
echo "Plugin"
if command -v claude >/dev/null 2>&1; then
  INSTALLED="$(claude plugin list 2>/dev/null | grep -oE 'varde@[A-Za-z0-9._-]+' | head -n 1)"
  if [ -n "$INSTALLED" ]; then
    VERSION="$(claude plugin list 2>/dev/null | grep -A3 "$INSTALLED" | grep -oE 'Version: *[0-9.]+' | head -n 1 | sed 's/Version: *//')"
    echo "ok      installed as $INSTALLED${VERSION:+ $VERSION}"
  else
    echo "warn    not installed through a marketplace (fine if you are running with --plugin-dir)"
  fi
else
  echo "warn    the claude command is not on PATH, so the install could not be checked"
fi

[ -f "$PLUGIN_ROOT/hooks/hooks.json" ] \
  && echo "ok      hooks/hooks.json found at $PLUGIN_ROOT" \
  || echo "fail    hooks/hooks.json is missing from $PLUGIN_ROOT"

# Where the hooks keep their counters. Hooks get CLAUDE_PLUGIN_DATA from
# Claude Code; this script usually does not, so look in the usual places.
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DATA_DIR=""
for d in ${CLAUDE_PLUGIN_DATA:+"$CLAUDE_PLUGIN_DATA"} "$CONFIG_DIR"/plugins/data/varde-* "$CONFIG_DIR"/plugins/data/varde "$CONFIG_DIR"/varde-data "$HOME"/.claude/varde-data; do
  [ -d "$d" ] && { DATA_DIR="$d"; break; }
done
if [ -n "$DATA_DIR" ]; then
  echo "ok      session counters in $DATA_DIR"
else
  echo "info    no session counters yet (no hook has run since install)"
fi

# --- Hooks ----------------------------------------------------------------
echo "Hooks"
for hook in session-start prompt-checkpoint session-end; do
  f="$DATA_DIR/fired/$hook"
  if [ -n "$DATA_DIR" ] && [ -f "$f" ]; then
    t="$(cat "$f" 2>/dev/null)"
    if is_number "$t"; then
      echo "ok      $hook last ran $(ago $(( NOW - t )))"
    else
      echo "warn    $hook left an unreadable trace"
    fi
  elif [ "$hook" = session-end ]; then
    echo "info    session-end has not run yet. It runs when a session closes, so this is normal until one has."
  else
    echo "fail    $hook has never run. Hooks load when a session starts, so restart the session."
  fi
done

# --- Project --------------------------------------------------------------
echo "Project"
[ -d "$TARGET" ] || { echo "fail    no such folder: $TARGET"; exit 0; }
TARGET="$(cd "$TARGET" && pwd)"
ROOT="$(find_project_root "$TARGET")"
if [ -z "$ROOT" ]; then
  echo "fail    no .claude/varde.conf in $TARGET or above it. Run /varde:new here to set it up."
  exit 0
fi
[ "$ROOT" = "$TARGET" ] && echo "ok      project root is $ROOT" || echo "ok      project root is $ROOT (found above $TARGET)"

MARKER="$ROOT/.claude/varde.conf"
ID="$(conf_get "$MARKER" id)"
MODE="$(conf_get "$MARKER" sensitive)"
[ -n "$MODE" ] || MODE="$(conf_get "$MARKER" private)"
case "$ID" in ""|*[!A-Za-z0-9._-]*) echo "fail    the marker has no usable id, so the hooks ignore this project"; ID="" ;; *) echo "ok      id $ID" ;; esac
case "$MODE" in
  yes) echo "info    mode: sensitive (private/ and log/ stay out of git)" ;;
  no)  echo "info    mode: standard (private/ stays out of git, log/ is committed)" ;;
  *)   echo "warn    the marker has no sensitive= line; treating it as standard" ; MODE=no ;;
esac

if [ -f "$ROOT/STATUS.md" ]; then
  LINES="$(wc -l < "$ROOT/STATUS.md" | tr -d ' ')"
  if [ "$LINES" -gt "$STATUS_CAP" ]; then
    echo "warn    STATUS.md is $LINES lines (cap $STATUS_CAP). Move finished items into the log."
  else
    echo "ok      STATUS.md is $LINES lines, last changed $(ago $(( NOW - $(file_mtime "$ROOT/STATUS.md") )))"
  fi
else
  echo "fail    STATUS.md is missing"
fi

if [ -f "$ROOT/CLAUDE.md" ]; then
  grep -q '@STATUS.md' "$ROOT/CLAUDE.md" \
    && echo "ok      CLAUDE.md imports STATUS.md" \
    || echo "fail    CLAUDE.md has no @STATUS.md line, so the status is not loaded each session"
else
  echo "fail    CLAUDE.md is missing"
fi

MONTH_LOG="$ROOT/log/$(date +%Y-%m).md"
if [ -f "$MONTH_LOG" ]; then
  DECISIONS="$(cat "$ROOT"/log/*.md 2>/dev/null | grep -c '^- *Decided:')"
  echo "ok      log/$(date +%Y-%m).md exists ($DECISIONS decisions across the log)"
elif [ -d "$ROOT/log" ]; then
  echo "info    no log entry yet this month"
else
  echo "warn    no log/ folder"
fi

if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$ROOT" check-ignore -q private/probe \
    && echo "ok      private/ is ignored by git" \
    || echo "fail    private/ is NOT ignored by git"
  if git -C "$ROOT" check-ignore -q log/probe.md; then
    [ "$MODE" = yes ] && echo "ok      log/ is ignored by git, as a sensitive project should be" \
                      || echo "warn    log/ is ignored by git, but the mode is standard. Remove the log/ line from .gitignore to commit it."
  else
    [ "$MODE" = yes ] && echo "fail    log/ is NOT ignored, but the mode is sensitive. Add log/ to .gitignore." \
                      || echo "ok      log/ is committed, as a standard project should be"
  fi
else
  echo "info    not a git repository"
fi

# --- Session --------------------------------------------------------------
echo "Session"
NP="${VARDE_NUDGE_PROMPTS:-8}";  NPS="default"; [ -n "$VARDE_NUDGE_PROMPTS" ] && NPS="override"
NM="${VARDE_NUDGE_MINUTES:-20}"; NMS="default"; [ -n "$VARDE_NUDGE_MINUTES" ] && NMS="override"
IS="${VARDE_IDLE_SECONDS:-600}"; ISS="default"; [ -n "$VARDE_IDLE_SECONDS" ] && ISS="override"
MP="${VARDE_MIN_PROMPTS:-3}";    MPS="default"; [ -n "$VARDE_MIN_PROMPTS" ] && MPS="override"
IL="${VARDE_INDEX_LINES:-15}";   ILS="default"; [ -n "$VARDE_INDEX_LINES" ] && ILS="override"
echo "info    reminder after $NP prompts ($NPS) and $NM minutes ($NMS) without a status change"
echo "info    a session counts as over after $IS s idle ($ISS); recovery needs $MP unsaved prompts ($MPS)"
echo "info    log index shows up to $IL decisions ($ILS)"

if [ -n "$ID" ] && [ -n "$DATA_DIR" ] && [ -d "$DATA_DIR/projects/$ID" ]; then
  SID="${CLAUDE_CODE_SESSION_ID:-}"
  if [ -n "$SID" ] && [ -f "$DATA_DIR/projects/$ID/$SID" ]; then
    state_load "$DATA_DIR/projects/$ID/$SID"
    echo "ok      this session: $S_prompts_since_status prompts since the status changed, $S_prompts_since_nudge since the last reminder, started $(ago $(( NOW - S_started )))"
    [ "$S_last_nudge" -gt 0 ] && echo "info    last reminder $(ago $(( NOW - S_last_nudge )))"
  else
    COUNT="$(ls "$DATA_DIR/projects/$ID" 2>/dev/null | grep -vc '\.tmp\.')"
    echo "warn    this session has no counters yet ($COUNT other sessions recorded). The start hook runs when a session begins, so restart if this session predates the install."
  fi
else
  echo "warn    no sessions recorded for this project yet"
fi

exit 0
