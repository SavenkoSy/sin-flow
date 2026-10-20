#!/usr/bin/env bash
launcher=$(sed -n 's/^handoff:[[:space:]]*//p' "${FLOW_HOME:-$HOME/.claude/sin-flow}/user.md" 2>/dev/null | sed 's/[[:space:]]#.*//; s/^"//; s/"$//' | head -1)
keep='sin-flow-handoff|progress\.md'
[[ $launcher == */* ]] && keep="$keep|${launcher##*/}"
jq -r --arg hand "$keep" '
  def ts: (.timestamp // "") | if . == "" then "           " else .[5:16] | sub("T";" ") end;
  def clip(n): if length > n then .[:n] + " …[+\(length - n)]" else . end;
  def cmdname: (capture("<command-name>(?<c>[^<]*)") | .c) // "?";
  def cmdargs: ((capture("<command-args>(?<a>[^<]*)") | .a) // "");
  if .isCompactSummary == true then "\(ts) === COMPACTION SUMMARY ==="
  elif .type == "user" then
    (.message.content | if type == "string" then [{type:"text", text:.}] else . end) as $c
    | ($c | map(select(.type=="text")) | map(.text) | join("\n")) as $t
    | ($c | map(select(.type=="tool_result")) | length) as $nr
    | if ($t | test("<command-name>")) then "\(ts) CMD: \($t | cmdname) \($t | cmdargs)"
      elif ($t | test("^(Another Claude session|\\[Subagent)")) then "\(ts) AGENT: \($t | clip(700))"
      elif ($t | startswith("Base directory for this skill")) then "\(ts) SKILL: \($t | clip(200))"
      elif ($t | length) > 0 and (($t | startswith("<")) | not) then "\(ts) USER: \($t | if test("^# ") then clip(700) else . end)"
      elif $nr > 0 then ts as $ts | $c[] | select(.type=="tool_result") | (.content | if type=="array" then map(.text? // "") | join("\n") else tostring end) | [splits("\n") | select(test("^(tab|session|account|config|opened|continue in this session):|^exit=|^paste into a new terminal tab|^cd .* && claude -n |exited [0-9]+: no tab opened"))] | select(length > 0) | "\($ts) RESULT: \(join(" | ") | clip(300))"
      elif ($t | length) > 0 then "\(ts) USER(sys): \($t | clip(160))"
      else empty end
  elif .type == "assistant" then
    ts as $t | (.message.usage // {}) as $u |
    .message.content[]? |
    if .type == "text" then "\($t) ASSISTANT: \(.text | clip(600))"
    elif .type == "tool_use" then
      ((.input.command // "") | test($hand)) as $keep | "\($t) TOOL: \(.name) \((.input | (.command // .skill // .description // .file_path // .prompt // .pattern // "")) | tostring | gsub("\n"; " ⏎ ") | clip(if $keep then 800 else 140 end))"
    else empty end
  elif .type == "attachment" and .attachment.type? == "queued_command" and .attachment.humanTurn? == true then "\(ts) USER(queued): \(.attachment.prompt | tostring)"
  elif .type == "system" then "\(ts) SYSTEM[\(.subtype // "")]: \((.content // .message // "") | tostring | clip(200))"
  else empty end
' "$1"
