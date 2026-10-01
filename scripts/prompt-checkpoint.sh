#!/bin/bash
# varde UserPromptSubmit hook.
#
# Runs each time a prompt is sent. It counts prompts, and when enough work
# has piled up since STATUS.md last changed, it prints a short reminder
# that Claude sees alongside the prompt. Claude then saves the status as
# part of the turn it was already going to take.
#
# Test overrides:
#   VARDE_NUDGE_PROMPTS  prompts before a nudge   (default 8)
#   VARDE_NUDGE_MINUTES  minutes before a nudge   (default 20)

. "$(dirname "$0")/lib.sh"
varde_setup

NUDGE_PROMPTS="${VARDE_NUDGE_PROMPTS:-8}"
NUDGE_MINUTES="${VARDE_NUDGE_MINUTES:-20}"
is_number "$NUDGE_PROMPTS" || NUDGE_PROMPTS=8
is_number "$NUDGE_MINUTES" || NUDGE_MINUTES=20

MODE="$(json_string permission_mode)"
STATUS_MTIME="$(file_mtime "$STATUS_FILE")"

state_load "$STATE_FILE"
[ "$S_started" -gt 0 ] || S_started="$NOW"
[ -n "$S_transcript" ] || S_transcript="$TRANSCRIPT"

# STATUS.md changed since the last check (by Claude, by hand, or by a
# git pull). Whoever did it, the status is fresh, so start counting again.
if [ "$STATUS_MTIME" -gt "$S_status_mtime_seen" ]; then
  S_status_mtime_seen="$STATUS_MTIME"
  S_prompts_since_status=0
  S_prompts_since_nudge=0
fi

S_prompts_since_status=$(( S_prompts_since_status + 1 ))
S_prompts_since_nudge=$(( S_prompts_since_nudge + 1 ))
S_last_prompt="$NOW"
S_ended=0

# The clock starts at whichever happened last: the status changed, a
# nudge was printed, or the session began.
BASE="$STATUS_MTIME"
[ "$S_last_nudge" -gt "$BASE" ] && BASE="$S_last_nudge"
[ "$S_started" -gt "$BASE" ] && BASE="$S_started"

NUDGE=no
if [ "$S_prompts_since_nudge" -ge "$NUDGE_PROMPTS" ] \
   && [ $(( NOW - BASE )) -ge $(( NUDGE_MINUTES * 60 )) ] \
   && [ "$MODE" != "plan" ] \
   && [ -f "$STATUS_FILE" ]; then
  NUDGE=yes
  S_last_nudge="$NOW"
  S_prompts_since_nudge=0
fi

state_save "$STATE_FILE"

if [ "$NUDGE" = yes ]; then
  TODAY="$(date +%Y-%m-%d)"
  LOG_FILE="log/$(date +%Y-%m).md"
  printf '[varde] Checkpoint. After finishing the request above, update STATUS.md (keep it under 60 lines) and add what was finished, decided, or tried and dropped to %s under "## %s". Say in one line that you did. If nothing worth recording has happened, skip it and say nothing.\n' "$LOG_FILE" "$TODAY"
fi

exit 0
