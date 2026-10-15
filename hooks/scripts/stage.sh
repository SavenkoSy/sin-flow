#!/bin/bash

flow_n_from_path() {
  local base n
  base=$(basename "$1")
  base=${base%.*}
  case "$base" in
    plan|spec|seed) base=$(basename "$(dirname "$1")") ;;
  esac
  base=$(printf '%s' "$base" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}_//')
  n=$(printf '%s' "$base" | sed -nE 's/.*batch-([0-9]+).*/batch-\1/p' | head -1)
  [ -n "$n" ] || n=$(printf '%s' "$base" | sed -nE 's/.*epic-([0-9]+(-[0-9]+)?).*/epic-\1/p' | head -1)
  [ -n "$n" ] || n=$(printf '%s' "$base" | sed -nE 's/.*[Gg][Hh]-?([0-9]+).*/\1/p' | head -1)
  [ -n "$n" ] || n=$(printf '%s' "$base" | grep -oE '(^|[^0-9])[0-9]{1,5}(-[0-9]+)?([^0-9]|$)' | head -1 | tr -cd '0-9-')
  printf '%s' "${n:-$base}"
}

flow_ticket_from_args() {
  local n
  n=$(printf '%s' "$1" | sed -nE 's#.*/(issues|pull)/([0-9]+).*#\2#p' | head -1)
  [ -n "$n" ] || n=$(printf '%s' "$1" | sed -nE 's/.*GH-?([0-9]+).*/\1/p' | head -1)
  [ -n "$n" ] || n=$(printf '%s' "$1" | sed -nE 's/.*epic ([0-9]+).*/epic-\1/p' | head -1)
  [ -n "$n" ] || n=$(printf '%s' "$1" | sed -nE 's/.*#([0-9]{1,5}).*/\1/p' | head -1)
  [ -n "$n" ] || n=$(printf '%s' "$1" | grep -oE '(^|[^0-9])[0-9]{1,5}([^0-9]|$)' | head -1 | tr -cd '0-9')
  printf '%s' "${n:-x}"
}

flow_goal_skill() {
  printf '%s' "$1" | sed -nE 's#.*[[:space:]](sin-flow:[a-z]+)[[:space:]][^:]*:[[:space:]](.*)$#\1 \2#p' | head -1
}

flow_stage() {
  local sid="$1" transcript="$2" dir cache cmd args skill stage n first latest="" latest_args=""
  dir="$HOME/.claude/state/sessions"
  cache="$dir/$sid.flow-stage"
  if [ -n "$transcript" ] && [ -f "$transcript" ]; then
    while IFS=$'\t' read -r cmd args; do
      if [ "$cmd" = goal ]; then
        read -r skill args <<<"$(flow_goal_skill "$args")"
      else
        skill=$cmd
      fi
      case "$skill" in
        sin-flow:setup|sin-flow:sync|sin-flow:ingest|sin-flow:plan|sin-flow:exec|sin-flow:review|sin-flow:learning) latest=$skill latest_args=$args ;;
      esac
    done < <(grep -F '<command-name>/' "$transcript" | jq -r 'select(.type=="user") | .message.content | if type=="string" then . else (map(select(.type=="text")) | map(.text) | join("\n")) end | select(test("<command-name>/(sin-flow:[a-z]+|goal)</command-name>")) | [(capture("<command-name>/(?<c>[a-z:-]+)</command-name>").c), ((capture("<command-args>(?<a>[\\s\\S]*?)</command-args>").a // "") | gsub("\\s+";" "))] | @tsv' 2>/dev/null)
  fi
  if [ -s "$cache" ] && { [ -z "$latest" ] || [ "$(cut -d' ' -f3 "$cache")" = "$latest" ]; }; then
    cat "$cache"
    return 0
  fi
  [ -n "$latest" ] || return 0
  skill=$latest
  args=$latest_args
  stage=${skill#sin-flow:}
  first=$(printf '%s' "$args" | awk '{print $1}')
  case "$stage" in
    plan|exec)
      n=$(flow_n_from_path "$first")
      case "$n" in *[0-9]*) ;; *) n=$(flow_ticket_from_args "$args") ;; esac
      ;;
    sync)
      n=$(printf '%s' "$first" | tr 'A-Z' 'a-z')
      ;;
    ingest|review) n=$(flow_ticket_from_args "$args") ;;
    *) n=x ;;
  esac
  mkdir -p "$dir"
  printf '%s %s %s\n' "$stage" "${n:-x}" "$skill" > "$cache"
  cat "$cache"
}

flow_repo_key() {
  local dir="$1" stage="$2" n="$3" key
  if [ "$stage" = sync ] && [ -f "$HOME/.claude/sin-flow/profiles/$n/profile.md" ]; then
    printf '%s' "$n"
    return 0
  fi
  case "$dir/" in
    "$HOME"/.claude/sin-flow/work/*/*)
      key=${dir#"$HOME"/.claude/sin-flow/work/}; key=${key%%/*}
      [ -f "$HOME/.claude/sin-flow/profiles/$key/profile.md" ] || key="?"
      ;;
  esac
  [ -z "$key" ] && [ -n "$dir" ] && [ -d "$dir" ] && key=$("${CLAUDE_PLUGIN_ROOT}/bin/sin-flow-profile" key "$dir" 2>/dev/null)
  if [ -z "$key" ] && [ -n "$dir" ]; then
    local profile repo_path
    for profile in "$HOME"/.claude/sin-flow/profiles/*/profile.md; do
      repo_path=$(sed -n 's/^repo\.path: *//p' "$profile" | head -1)
      repo_path=${repo_path/#\~/$HOME}
      [ -n "$repo_path" ] || continue
      case "$dir/" in
        "$repo_path"/*|*/"$(basename "$repo_path")"/*) key=$(basename "$(dirname "$profile")"); break ;;
      esac
    done
  fi
  printf '%s' "${key:-?}"
}
