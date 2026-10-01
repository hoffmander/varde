#!/bin/bash
# varde SessionEnd hook.
#
# All hooks at session end share about 1.5 seconds, and Claude is already
# gone, so this only records that the session closed cleanly. The next
# session's start hook decides whether anything went unsaved.
#
# A closed window or a crash never reaches this script. That case is
# caught by the idle check in session-start.sh.

. "$(dirname "$0")/lib.sh"
varde_setup

# Nothing was recorded for this session, so there is nothing to close.
[ -f "$STATE_FILE" ] || exit 0

state_load "$STATE_FILE"
S_ended="$NOW"
state_save "$STATE_FILE"

exit 0
