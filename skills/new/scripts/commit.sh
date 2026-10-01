#!/bin/bash
# varde first commit. Commits only the files varde created, so anything
# else already in the folder (staged or not) is left exactly as it was.
#
# Usage:  bash commit.sh <target-folder> <commit message>

TARGET="$1"
MESSAGE="$2"

if [ -z "$TARGET" ] || [ -z "$MESSAGE" ]; then
  echo "error   usage: commit.sh <target-folder> <commit message>"
  exit 1
fi
cd "$TARGET" || { echo "error   no such folder: $TARGET"; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "error   not a git repository"; exit 1; }

# Collect the varde files that exist and that .gitignore does not exclude
# (in a private project, log/ is excluded on purpose).
PATHS=()
for path in CLAUDE.md STATUS.md .gitignore .claude/varde.conf log; do
  [ -e "$path" ] || continue
  git check-ignore -q "$path" 2>/dev/null && continue
  PATHS+=("$path")
done

if [ "${#PATHS[@]}" -eq 0 ]; then
  echo "skipped commit (nothing to add)"
  exit 0
fi

git add -- "${PATHS[@]}" || { echo "error   git add failed"; exit 1; }

if git diff --cached --quiet -- "${PATHS[@]}"; then
  echo "skipped commit (no changes in varde files)"
  exit 0
fi

git commit -q -m "$MESSAGE" -- "${PATHS[@]}" || { echo "error   git commit failed"; exit 1; }
echo "created commit $(git rev-parse --short HEAD): $MESSAGE"
exit 0
