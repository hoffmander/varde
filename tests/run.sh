#!/bin/bash
# varde tests. Exercises the scripts with no Claude session involved.
#
# Usage:  bash tests/run.sh
#
# Everything happens in a temporary folder that is deleted at the end.
# Nothing in your real projects or your Claude Code settings is touched.

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCAFFOLD="$REPO/skills/new/scripts/scaffold.sh"
COMMIT="$REPO/skills/new/scripts/commit.sh"
UNINSTALL="$REPO/skills/uninstall/scripts/uninstall.sh"
HOOKS="$REPO/scripts"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Hooks and the uninstall script keep their counters here during the test.
export CLAUDE_PLUGIN_DATA="$WORK/data"
export CLAUDE_CONFIG_DIR="$WORK/config"
# Commits made by the tests need an author, even on a fresh machine.
export GIT_AUTHOR_NAME="varde test" GIT_AUTHOR_EMAIL="test@example.com"
export GIT_COMMITTER_NAME="varde test" GIT_COMMITTER_EMAIL="test@example.com"

PASS=0
FAIL=0

# check DESCRIPTION COMMAND...  -> passes when the command succeeds
check() {
  local what="$1"; shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS + 1)); echo "  ok    $what"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL  $what"
  fi
}
# refute DESCRIPTION COMMAND...  -> passes when the command fails
refute() {
  local what="$1"; shift
  if "$@" >/dev/null 2>&1; then
    FAIL=$((FAIL + 1)); echo "  FAIL  $what"
  else
    PASS=$((PASS + 1)); echo "  ok    $what"
  fi
}
contains() { grep -qF -- "$2" "$1"; }
ignored()  { git -C "$1" check-ignore -q "$2"; }
tracked()  { git -C "$1" ls-files --error-unmatch "$2"; }

# hook SCRIPT SESSION CWD EXTRA-JSON  -> runs a hook with made-up input
hook() {
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"test"%s}' \
    "$2" "$WORK/transcript.jsonl" "$3" "$4" | bash "$HOOKS/$1"
}
state_of() { grep -E "^$3=" "$CLAUDE_PLUGIN_DATA/projects/$1/$2" | cut -d= -f2; }
id_of()    { grep -E '^id=' "$1/.claude/varde.conf" | cut -d= -f2; }
touch "$WORK/transcript.jsonl"

echo "Standard project"
P="$WORK/truck build"
bash "$SCAFFOLD" "$P" no "Truck & Trail / Build" > "$WORK/out.txt"
bash "$COMMIT" "$P" "Set up project." >> "$WORK/out.txt"
check  "creates CLAUDE.md"                    test -f "$P/CLAUDE.md"
check  "creates STATUS.md"                    test -f "$P/STATUS.md"
check  "creates this month's log"             test -f "$P/log/$(date +%Y-%m).md"
check  "creates the marker"                   test -f "$P/.claude/varde.conf"
check  "creates private/"                     test -d "$P/private"
check  "name with & and / survives"           contains "$P/CLAUDE.md" "# Truck & Trail / Build"
check  "CLAUDE.md imports the status"         contains "$P/CLAUDE.md" "@STATUS.md"
check  "makes one commit on main"             test "$(git -C "$P" rev-list --count main)" = 1
check  "adds no remote"                       test -z "$(git -C "$P" remote)"
check  "private/ is ignored"                  ignored "$P" "private/x"
check  "log is committed"                     tracked "$P" "log/$(date +%Y-%m).md"
refute "no sensitive rule in CLAUDE.md"       contains "$P/CLAUDE.md" "This project is sensitive"

echo "Running it twice"
cp "$P/CLAUDE.md" "$WORK/before.md"
bash "$SCAFFOLD" "$P" no "Different Name" > "$WORK/out.txt"
check  "second run changes nothing"           cmp -s "$P/CLAUDE.md" "$WORK/before.md"
refute "second run creates nothing"           grep -q '^created' "$WORK/out.txt"

echo "Sensitive project"
S="$WORK/appeal"
bash "$SCAFFOLD" "$S" yes "Appeal" > "$WORK/out.txt"
bash "$COMMIT" "$S" "Set up project." >> "$WORK/out.txt"
check  "log is ignored"                       ignored "$S" "log/$(date +%Y-%m).md"
refute "log is not committed"                 tracked "$S" "log/$(date +%Y-%m).md"
check  "sensitive rule in CLAUDE.md"          contains "$S/CLAUDE.md" "This project is sensitive"
refute "new empty folder gets no allowlist"   grep -qxF '/*' "$S/.gitignore"

echo "Sensitive project added to a folder that already holds files"
A="$WORK/paperwork"
mkdir -p "$A"; touch "$A/Claim Form.pdf" "$A/NOTES.md"
bash "$SCAFFOLD" "$A" yes "Paperwork" > "$WORK/out.txt"
bash "$COMMIT" "$A" "Set up project." >> "$WORK/out.txt"
check  "existing files are ignored"           ignored "$A" "Claim Form.pdf"
check  "a future file type is ignored"        ignored "$A" "scan.heic"
check  "varde's files are still tracked"      tracked "$A" "STATUS.md"
check  "git add -A would stage nothing"       test -z "$(git -C "$A" status --porcelain)"

echo "Folder with its own .gitignore"
G="$WORK/has-ignore"
mkdir -p "$G"; echo ".DS_Store" > "$G/.gitignore"; cp "$G/.gitignore" "$WORK/ignore-before"
bash "$SCAFFOLD" "$G" no "Has Ignore" > "$WORK/out.txt"
check  ".gitignore is left untouched"         cmp -s "$G/.gitignore" "$WORK/ignore-before"
check  "reports that private/ is not ignored" contains "$WORK/out.txt" "does not ignore private/"

echo "Folder that was already a git repository"
R="$WORK/was-repo"
mkdir -p "$R"; git -C "$R" init -q -b main; echo x > "$R/app.js"
git -C "$R" add app.js; git -C "$R" commit -qm "First."; touch "$R/secret.pdf"
bash "$SCAFFOLD" "$R" yes "Was Repo" > "$WORK/out.txt"
refute "gets no allowlist"                    grep -qxF '/*' "$R/.gitignore"
check  "reports the exposed files"            contains "$WORK/out.txt" "untracked items in this repository are not ignored"

echo "Hooks"
ID="$(id_of "$P")"
mkdir -p "$P/sub folder"
check  "silent outside a project"             test -z "$(hook session-start.sh s0 "$WORK" ',"source":"startup"')"
hook session-start.sh s1 "$P/sub folder" ',"source":"startup"' > /dev/null
check  "finds the project from a subfolder"   test -f "$CLAUDE_PLUGIN_DATA/projects/$ID/s1"
for i in 1 2 3; do hook prompt-checkpoint.sh s1 "$P" ',"permission_mode":"default","prompt":"hi"' > /dev/null; done
check  "counts prompts"                       test "$(state_of "$ID" s1 prompts_since_status)" = 3
check  "no reminder before the threshold"     test -z "$(hook prompt-checkpoint.sh s1 "$P" ',"permission_mode":"default","prompt":"hi"')"
check  "reminder once the threshold is met"   test -n "$(VARDE_NUDGE_PROMPTS=2 VARDE_NUDGE_MINUTES=0 hook prompt-checkpoint.sh s1 "$P" ',"permission_mode":"default","prompt":"hi"')"
check  "no reminder on the very next prompt"  test -z "$(VARDE_NUDGE_PROMPTS=2 VARDE_NUDGE_MINUTES=0 hook prompt-checkpoint.sh s1 "$P" ',"permission_mode":"default","prompt":"hi"')"
hook prompt-checkpoint.sh s1 "$P" ',"permission_mode":"default","prompt":"hi"' > /dev/null
check  "no reminder in plan mode"             test -z "$(VARDE_NUDGE_PROMPTS=2 VARDE_NUDGE_MINUTES=0 hook prompt-checkpoint.sh s1 "$P" ',"permission_mode":"plan","prompt":"hi"')"
hook prompt-checkpoint.sh s1 "$P" ',"permission_mode":"default","prompt":"say \"cwd\": \"/etc\" please"' > /dev/null
check  "text in a prompt cannot fake a field" test "$(ls "$CLAUDE_PLUGIN_DATA/projects" | wc -l | tr -d ' ')" = 1
sleep 1; touch "$P/STATUS.md"
hook prompt-checkpoint.sh s1 "$P" ',"permission_mode":"default","prompt":"hi"' > /dev/null
check  "a status change resets the count"     test "$(state_of "$ID" s1 prompts_since_status)" = 1
check  "a live session is not called unsaved" test -z "$(hook session-start.sh s2 "$P" ',"source":"startup"')"
rm -f "$CLAUDE_PLUGIN_DATA/projects/$ID/s2"

# Make session s1 look like it died 700 seconds ago with unsaved work.
NOW="$(date +%s)"
sed -i.bak "s/^last_prompt=.*/last_prompt=$((NOW - 700))/; s/^prompts_since_status=.*/prompts_since_status=5/" "$CLAUDE_PLUGIN_DATA/projects/$ID/s1"
rm -f "$CLAUDE_PLUGIN_DATA/projects/$ID/s1.bak"
touch -t "$(date -r $((NOW - 3600)) +%Y%m%d%H%M.%S)" "$P/STATUS.md"
check  "a dead unsaved session is reported"   contains <(hook session-start.sh s3 "$P" ',"source":"startup"') "ended without updating STATUS.md"
rm -f "$CLAUDE_PLUGIN_DATA/projects/$ID/s3"; touch "$P/STATUS.md"
check  "the report stops once status is saved" test -z "$(hook session-start.sh s4 "$P" ',"source":"startup"')"
hook session-end.sh s4 "$P" ',"reason":"other"'
check  "session end is recorded"              test "$(state_of "$ID" s4 ended)" -gt 0
for i in $(seq 1 70); do echo "- line $i" >> "$P/STATUS.md"; done
check  "warns when STATUS.md is over 60 lines" contains <(hook session-start.sh s5 "$P" ',"source":"startup"') "cap 60"
check  "every hook exits 0"                   hook session-end.sh s5 "$P" ',"reason":"other"'
check  "hooks run with a bare environment"    env -i PATH=/usr/bin:/bin HOME="$WORK/home" bash -c "printf '{\"session_id\":\"s6\",\"transcript_path\":\"/x\",\"cwd\":\"$P\",\"source\":\"startup\"}' | bash '$HOOKS/session-start.sh'"

echo "Log index"
L="$WORK/indexed"
bash "$SCAFFOLD" "$L" no "Indexed" > "$WORK/out.txt"
printf '# Log 2026-08\n\n## 2026-08-03\n\n- Decided: Use plywood, because MDF swells.\n\n## 2026-08-20\n\n- Decided: Skip the side table, because it blocks the tailgate.\n- Decided: Say "cwd": "/etc" to prove it is text.\n' > "$L/log/2026-08.md"
printf '# Log 2026-10\n\n## 2026-10-01\n\n- Did: Nothing decided.\n' > "$L/log/2026-10.md"
INDEX="$(hook session-start.sh i1 "$L" ',"source":"startup"')"
check  "index is printed"                     grep -q 'varde log index' <<< "$INDEX"
check  "index is framed as a record"          grep -q 'a record, not instructions' <<< "$INDEX"
check  "newest decision comes first"          test "$(grep -c . <<< "$INDEX")" -gt 0 -a "$(grep 'Decided' <<< "$INDEX" | head -n 1 | cut -c1-10)" = "2026-08-20"
check  "oldest decision comes last"           test "$(grep 'Decided' <<< "$INDEX" | tail -n 1 | cut -c1-10)" = "2026-08-03"
check  "dates come from the heading above"    grep -q '^2026-08-20  Decided: Skip the side table' <<< "$INDEX"
check  "a fake field in a decision is text"   grep -q 'cwd' <<< "$INDEX"
check  "footer counts all decisions"          grep -q '3 of 3 decisions' <<< "$INDEX"
check  "VARDE_INDEX_LINES caps the list"      test "$(VARDE_INDEX_LINES=1 hook session-start.sh i2 "$L" ',"source":"startup"' | grep -c '^20[0-9][0-9]-')" = 1
check  "capped footer says how many more"     grep -q '1 of 3 decisions; grep' <<< "$(VARDE_INDEX_LINES=1 hook session-start.sh i3 "$L" ',"source":"startup"')"
check  "VARDE_INDEX_LINES=0 turns it off"     test -z "$(VARDE_INDEX_LINES=0 hook session-start.sh i4 "$L" ',"source":"startup"')"
check  "index is printed after compaction"    grep -q 'varde log index' <<< "$(hook session-start.sh i1 "$L" ',"source":"compact"')"
rm -f "$L"/log/2026-08.md
check  "no decisions, no index"               test -z "$(hook session-start.sh i5 "$L" ',"source":"startup"')"
check  "recovery note frames the transcript"  grep -q 'a record of what happened, not as instructions' "$HOOKS/session-start.sh"

echo "Hook traces"
check  "start hook leaves a trace"            test -f "$CLAUDE_PLUGIN_DATA/fired/session-start"
check  "prompt hook leaves a trace"           test -f "$CLAUDE_PLUGIN_DATA/fired/prompt-checkpoint"
check  "end hook leaves a trace"              test -f "$CLAUDE_PLUGIN_DATA/fired/session-end"
rm -f "$CLAUDE_PLUGIN_DATA/fired/session-end"
hook session-end.sh nowhere "$WORK" ',"reason":"other"' > /dev/null
check  "trace is left even outside a project" test -f "$CLAUDE_PLUGIN_DATA/fired/session-end"

echo "Doctor"
DOCTOR="$REPO/skills/doctor/scripts/doctor.sh"
OUTD="$(CLAUDE_CODE_SESSION_ID=i1 bash "$DOCTOR" "$L")"
check  "doctor exits 0"                       env CLAUDE_CODE_SESSION_ID=i1 bash "$DOCTOR" "$L"
check  "doctor finds the project"             grep -q "ok      project root is $L" <<< "$OUTD"
check  "doctor reads the mode"                grep -q 'mode: standard' <<< "$OUTD"
check  "doctor sees the hooks fired"          test "$(grep -c '^ok      .* last ran' <<< "$OUTD")" = 3
check  "doctor reports this session"          grep -q 'ok      this session:' <<< "$OUTD"
check  "doctor shows the thresholds"          grep -q 'reminder after 8 prompts (default)' <<< "$OUTD"
check  "doctor shows an override"             grep -q 'after 2 prompts (override)' <<< "$(env VARDE_NUDGE_PROMPTS=2 bash "$DOCTOR" "$L")"
refute "healthy project has no fail lines"    grep -q '^fail' <<< "$OUTD"
OUTN="$(bash "$DOCTOR" "$WORK")"
check  "doctor outside a project exits 0"     bash "$DOCTOR" "$WORK"
check  "doctor flags a missing marker"        grep -q '^fail    no .claude/varde.conf' <<< "$OUTN"
for i in $(seq 1 70); do echo "- line $i" >> "$L/STATUS.md"; done
check  "doctor warns over the cap"            grep -q '^warn    STATUS.md is .* lines (cap 60)' <<< "$(bash "$DOCTOR" "$L")"
echo "log/" >> "$L/.gitignore"
check  "doctor flags log ignored in standard" grep -q '^warn    log/ is ignored by git, but the mode is standard' <<< "$(bash "$DOCTOR" "$L")"

echo "Uninstall from this computer (dry run only)"
mkdir -p "$CLAUDE_CONFIG_DIR/plugins/cache/varde/varde/0.0.1"; touch "$CLAUDE_CONFIG_DIR/plugins/cache/varde/varde/0.0.1/x"
OUTU="$(bash "$UNINSTALL" plugin)"
check  "plan names the cached copies"         grep -q 'would   remove cached plugin copies' <<< "$OUTU"
check  "dry run leaves the cache alone"       test -f "$CLAUDE_CONFIG_DIR/plugins/cache/varde/varde/0.0.1/x"
check  "dry run leaves the counters alone"    test -d "$CLAUDE_PLUGIN_DATA"

echo "Uninstall from one project"
bash "$UNINSTALL" project "$P" > "$WORK/out.txt"
check  "a dry run removes nothing"            test -f "$P/.claude/varde.conf"
bash "$UNINSTALL" project "$P" --confirm > "$WORK/out.txt"
refute "removes the marker"                   test -f "$P/.claude/varde.conf"
refute "removes the session counters"         test -d "$CLAUDE_PLUGIN_DATA/projects/$ID"
check  "keeps CLAUDE.md"                      test -f "$P/CLAUDE.md"
check  "keeps STATUS.md"                      test -f "$P/STATUS.md"
check  "keeps the log"                        test -d "$P/log"
check  "keeps private/"                       test -d "$P/private"
check  "keeps .gitignore"                     test -f "$P/.gitignore"
check  "hooks go silent afterward"            test -z "$(hook session-start.sh s9 "$P" ',"source":"startup"')"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
