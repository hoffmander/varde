#!/bin/bash
# varde scaffold. Creates the project files from the templates in ../assets.
#
# Usage:  bash scaffold.sh <target-folder> <sensitive: yes|no> <project name>
#
# Every project gets a private/ folder that git ignores.
# A sensitive project (medical, legal, financial, work-confidential) also
# keeps its session log out of git.
#
# Safe to run on a folder that already has things in it: a file that
# exists is never overwritten or edited. Each line of output says what
# happened, so the skill can report it:
#   created <path>
#   skipped <path> (already exists)
#   note    <something the skill should offer to fix or mention>

TARGET="$1"
SENSITIVE="$2"
NAME="$3"
TEMPLATES="$(cd "$(dirname "$0")/.." && pwd)/assets"

if [ -z "$TARGET" ] || [ -z "$NAME" ]; then
  echo "error   usage: scaffold.sh <target-folder> <yes|no> <project name>"
  exit 1
fi
case "$SENSITIVE" in yes|no) ;; *) echo "error   sensitive must be yes or no"; exit 1 ;; esac
if [ ! -d "$TEMPLATES" ]; then
  echo "error   templates folder not found at $TEMPLATES"
  exit 1
fi

# Look at the folder before touching it. Two facts decide how careful
# the .gitignore has to be in a sensitive project:
#   OTHER_FILES  how many things are already in the folder, not counting
#                what varde manages
#   WAS_REPO     whether it was already a git repository
OTHER_FILES=0
WAS_REPO=no
if [ -d "$TARGET" ]; then
  OTHER_FILES="$(ls -A "$TARGET" 2>/dev/null \
    | grep -vxE '\.DS_Store|\.git|\.gitignore|\.claude|CLAUDE\.md|STATUS\.md|log|private' \
    | wc -l | tr -d ' ')"
  git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1 && WAS_REPO=yes
fi

mkdir -p "$TARGET" || { echo "error   could not create $TARGET"; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"

# A sensitive project added to a folder that already holds files: those
# files sit in the folder's root, where one `git add` would pick them all
# up. In that case git is limited to varde's own files. Skipped when the
# folder was already a repository, since that would change what an
# existing project tracks.
ALLOWLIST=no
if [ "$SENSITIVE" = yes ] && [ "$OTHER_FILES" -gt 0 ] && [ "$WAS_REPO" = no ]; then
  ALLOWLIST=yes
fi

TODAY="$(date +%Y-%m-%d)"
MONTH="$(date +%Y-%m)"

# The id names this project's state folder. Folder name plus the time it
# was created, limited to characters that are safe in a path.
SLUG="$(basename "$TARGET" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-*$//')"
ID="${SLUG}-$(date +%s)"

SENSITIVE_RULE=""
if [ "$SENSITIVE" = yes ]; then
  SENSITIVE_RULE='- This project is sensitive. `log/` stays on this machine, but `STATUS.md` is committed. Keep account numbers, ID numbers, and personal details out of `STATUS.md` and commit messages.
'
fi

# write_new PATH CONTENT -> creates the file only if it isn't there.
write_new() {
  if [ -e "$1" ]; then
    echo "skipped ${1#$TARGET/} (already exists)"
    return 1
  fi
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" > "$1"
  echo "created ${1#$TARGET/}"
  return 0
}

# fill TEMPLATE -> prints the template with the simple placeholders
# filled in. Purpose, goals, and done are left for the skill to write,
# since they are free text from the interview.
fill() {
  local text
  text="$(cat "$TEMPLATES/$1")"
  text="${text//\{\{NAME\}\}/$NAME}"
  text="${text//\{\{DATE\}\}/$TODAY}"
  text="${text//\{\{SENSITIVE_RULE\}\}/$SENSITIVE_RULE}"
  printf '%s' "$text"
}

# --- CLAUDE.md -----------------------------------------------------------
if ! write_new "$TARGET/CLAUDE.md" "$(fill CLAUDE.md)"; then
  if ! grep -q '@STATUS.md' "$TARGET/CLAUDE.md" 2>/dev/null; then
    echo "note    CLAUDE.md has no @STATUS.md line, so status will not load each session"
  fi
fi

# --- STATUS.md -----------------------------------------------------------
write_new "$TARGET/STATUS.md" "$(fill STATUS.md)"

# --- log -----------------------------------------------------------------
write_new "$TARGET/log/$MONTH.md" "# Log $MONTH

## $TODAY

- Did: Project set up with varde."

# --- marker --------------------------------------------------------------
write_new "$TARGET/.claude/varde.conf" "# varde project marker. varde's hooks do nothing in a folder without it.
version=1
id=$ID
sensitive=$SENSITIVE
created=$TODAY"

# --- .gitignore ----------------------------------------------------------
IGNORE="$(cat "$TEMPLATES/gitignore")"
[ "$SENSITIVE" = yes ] && IGNORE="$IGNORE
$(cat "$TEMPLATES/gitignore-sensitive")"
[ "$ALLOWLIST" = yes ] && IGNORE="$IGNORE
$(cat "$TEMPLATES/gitignore-allowlist")"

if write_new "$TARGET/.gitignore" "$IGNORE"; then
  [ "$ALLOWLIST" = yes ] \
    && echo "note    git is limited to varde's files, because this folder already held $OTHER_FILES other items"
else
  # An existing .gitignore is left alone. Report what is still missing
  # so the skill can offer to add it.
  NEEDED="private/ .claude/settings.local.json"
  [ "$SENSITIVE" = yes ] && NEEDED="$NEEDED log/"
  for entry in $NEEDED; do
    grep -qxF "$entry" "$TARGET/.gitignore" 2>/dev/null \
      || echo "note    .gitignore does not ignore $entry"
  done
  if [ "$ALLOWLIST" = yes ] && ! grep -qxF '/*' "$TARGET/.gitignore" 2>/dev/null; then
    echo "note    .gitignore does not limit git to varde's files, and this folder holds $OTHER_FILES other items"
  fi
fi

# --- private folder ------------------------------------------------------
if [ -d "$TARGET/private" ]; then
  echo "skipped private/ (already exists)"
else
  mkdir -p "$TARGET/private" && echo "created private/"
fi

# --- git -----------------------------------------------------------------
if git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "skipped git init (already a repository)"
  # An existing repository keeps its own rules. In a sensitive project,
  # say how many files a `git add` would still pick up.
  if [ "$SENSITIVE" = yes ]; then
    LOOSE="$(git -C "$TARGET" status --porcelain 2>/dev/null | grep '^??' \
      | grep -vE '^\?\? "?(CLAUDE\.md|STATUS\.md|\.gitignore|\.claude/)' | wc -l | tr -d ' ')"
    [ "$LOOSE" -gt 0 ] && echo "note    $LOOSE untracked items in this repository are not ignored"
  fi
else
  git -C "$TARGET" init -q -b main && echo "created git repository on branch main"
fi

echo "mode    $( [ "$SENSITIVE" = yes ] && echo "sensitive: private/ and log/ stay out of git" || echo "standard: private/ stays out of git, log/ is committed" )"
echo "done    $TARGET"
exit 0
