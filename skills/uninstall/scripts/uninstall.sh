#!/bin/bash
# varde uninstall. Removes varde from one project, or from this computer.
#
# Usage:
#   bash uninstall.sh project <folder>            show what would change
#   bash uninstall.sh project <folder> --confirm  do it
#   bash uninstall.sh plugin                      show what would change
#   bash uninstall.sh plugin --confirm            do it
#
# Without --confirm nothing is changed. The script only prints a plan.
#
# What is never touched, in either mode: CLAUDE.md, STATUS.md, log/,
# private/, and .gitignore. Those hold the user's own work.
#
# Everything lives inside main() and main is called on the last line.
# Bash reads a script as it runs it, and "plugin" mode deletes the folder
# this file sits in. Wrapping it this way makes bash read the whole file
# before any of it runs.

main() {
  local mode="$1"
  local confirm=no
  local target=""

  case "$mode" in
    project)
      target="$2"
      [ "$3" = "--confirm" ] && confirm=yes
      ;;
    plugin)
      [ "$2" = "--confirm" ] && confirm=yes
      ;;
    *)
      echo "error   usage: uninstall.sh project <folder> [--confirm] | plugin [--confirm]"
      exit 1
      ;;
  esac

  # The places the hooks keep session counters: the plugin's data folder
  # (named after how the plugin was installed), the fallback folder, and
  # CLAUDE_PLUGIN_DATA when Claude Code has set it.
  local config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  local data_dirs
  data_dirs="$(ls -d "$config_dir"/plugins/data/varde-* "$config_dir"/plugins/data/varde \
    "$config_dir"/varde-data "$HOME"/.claude/varde-data ${CLAUDE_PLUGIN_DATA:+"$CLAUDE_PLUGIN_DATA"} 2>/dev/null | sort -u)"

  if [ "$mode" = project ]; then
    uninstall_project
  else
    uninstall_plugin
  fi
  exit 0
}

# act DESCRIPTION COMMAND...
# Prints what will happen. Runs it only when --confirm was given.
act() {
  local what="$1"; shift
  if [ "$confirm" = yes ]; then
    if "$@" >/dev/null 2>&1; then
      echo "removed $what"
    else
      echo "failed  $what"
    fi
  else
    echo "would   remove $what"
  fi
}

uninstall_project() {
  if [ -z "$target" ] || [ ! -d "$target" ]; then
    echo "error   no such folder: $target"
    exit 1
  fi
  target="$(cd "$target" && pwd)"
  local marker="$target/.claude/varde.conf"

  if [ ! -f "$marker" ]; then
    echo "note    $target is not a varde project (no .claude/varde.conf)"
    exit 0
  fi

  # The id names this project's session counters. Read with grep, never
  # run, and only used if it is made of safe characters.
  local id
  id="$(grep -E '^id=' "$marker" | head -n 1 | cut -d= -f2-)"
  case "$id" in ""|*[!A-Za-z0-9._-]*) id="" ;; esac

  act ".claude/varde.conf (the marker: varde's hooks stop running in this folder)" rm -f "$marker"

  if [ -n "$id" ]; then
    local dir
    for dir in $data_dirs; do
      [ -d "$dir/projects/$id" ] && act "session counters for this project" rm -rf "$dir/projects/$id"
    done
  fi

  # Remove .claude/ only if the marker was the last thing in it.
  if [ "$confirm" = yes ]; then
    rmdir "$target/.claude" 2>/dev/null && echo "removed .claude/ (it was empty)"
  fi

  local item
  for item in CLAUDE.md STATUS.md log private .gitignore; do
    [ -e "$target/$item" ] && echo "kept    $item"
  done
  echo "note    STATUS.md still loads each session through the @STATUS.md line in CLAUDE.md"
}

uninstall_plugin() {
  if ! command -v claude >/dev/null 2>&1; then
    echo "error   the claude command was not found on this computer's PATH"
    exit 1
  fi

  # Find how varde is installed, for example varde@varde.
  local installed
  installed="$(claude plugin list 2>/dev/null | grep -oE 'varde@[A-Za-z0-9._-]+' | sort -u)"

  if [ -z "$installed" ]; then
    echo "note    the varde plugin is not installed"
  fi

  local id
  for id in $installed; do
    act "plugin $id (both commands and all three hooks)" claude plugin uninstall "$id"
  done

  if claude plugin marketplace list 2>/dev/null | grep -qE '(^|[^A-Za-z0-9._-])varde([^A-Za-z0-9._-]|$)'; then
    act "marketplace varde (where updates came from)" claude plugin marketplace remove varde
  fi

  local dir
  for dir in $data_dirs; do
    [ -d "$dir" ] && act "session counters in $dir" rm -rf "$dir"
  done

  # Claude Code keeps a copy of every installed version here and does not
  # clear it on uninstall. This script may be running from inside it; that
  # is fine, because the whole file was read before main() started.
  local cache="$config_dir/plugins/cache/varde"
  [ -d "$cache" ] && act "cached plugin copies in $cache" rm -rf "$cache"

  echo "kept    every project folder, with its CLAUDE.md, STATUS.md, log/, and private/"
  echo "note    each project still has .claude/varde.conf. It does nothing without the plugin"
  echo "note    STATUS.md still loads each session through the @STATUS.md line in CLAUDE.md"
  [ "$confirm" = yes ] && echo "note    restart any open session to finish. Until then an open session can show a hook error on each prompt, because its hook scripts are gone"
}

main "$@"
