#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$root/skills/learning/scripts"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

export HOME="$scratch/home"
export FLOW_HOME="$scratch/flow"
export FLOW_LEARNING_DIR="$scratch/learning"
proj="$HOME/.claude/projects/-demo"
mkdir -p "$proj" "$FLOW_HOME" "$FLOW_LEARNING_DIR"
runs="$scratch/rows.tsv"
printf 'date\trepo\tstage\tn\tsession_id\taccount\tmodel\tstart\tend\tturns\tuser_turns\tctx_first_k\tctx_last_k\thandoff\tlimit_hits\tskill\n' > "$runs"

row() { printf '2026-01-02\tacme\t%s\t%s\t%s\tmain\topus\t-\t-\t%s\t%s\t10\t100\t%s\t0\tsin-flow:%s\n' "$1" "$2" "$3" "$4" "$5" "${6:-0}" "$1" >> "$runs"; }
assistant() { jq -nc --arg id "$2" --arg m "${3:-claude-opus-9}" --arg t "2026-01-02T10:${4:-00}:00.000Z" '{type:"assistant", timestamp:$t, message:{id:$id, model:$m, usage:{input_tokens:1000, cache_creation_input_tokens:0, cache_read_input_tokens:100000, output_tokens:1000}, content:[{type:"text", text:"working"}]}}' >> "$1"; }
user() { jq -nc --arg x "$2" --arg t "2026-01-02T10:${3:-01}:00.000Z" '{type:"user", timestamp:$t, message:{content:$x}}' >> "$1"; }
session() {
  local sid=$1 messages=$2 i
  for i in $(seq 1 "$messages"); do assistant "$proj/$sid.jsonl" "m$i"; done
}

for k in 01 02 03 04 05 06 07 08 09 10 11 12; do
  turns=10; user_turns=1
  [ "$k" = 02 ] && user_turns=5
  [ "$k" = 07 ] && turns=1
  row exec "$k" "sess$k-0000-0000" "$turns" "$user_turns"
  session "sess$k-0000-0000" 2
done
row exec 13 "sess13-0000-0000" 10 1
row plan 1 "plan01-0000-0000" 10 0 1
row plan 2 "plan02-0000-0000" 10 0 1
session plan01-0000-0000 1
session plan02-0000-0000 1

assistant "$proj/sess01-0000-0000.jsonl" m1
user "$proj/sess02-0000-0000.jsonl" "please do it another way" 05
assistant "$proj/sess02-0000-0000.jsonl" m9 claude-opus-9 06
jq -nc '{type:"attachment", timestamp:"2026-01-02T10:30:00.000Z", attachment:{text:"CTX GUARD: context is above the limit"}}' >> "$proj/sess03-0000-0000.jsonl"
user "$proj/sess04-0000-0000.jsonl" $'[Subagent hand-back]\nMODE: gate\nSTATUS: red\nPROFILE: acme\nNOTE: 3 failures\n' 20
user "$proj/sess05-0000-0000.jsonl" $'[Subagent hand-back]\nMODE: gate\nSTATUS: red\nPROFILE: acme\n' 10
user "$proj/sess05-0000-0000.jsonl" $'[Subagent hand-back]\nMODE: gate\nSTATUS: green\nPROFILE: acme\n' 12
user "$proj/sess05-0000-0000.jsonl" $'[Subagent hand-back]\nMODE: ship\nSTATUS: done\nPROFILE: acme\nPR: https://example.com/acme/shop/pull/7 (created)\n' 14
user "$proj/sess05-0000-0000.jsonl" $'[Subagent hand-back]\nMODE: commit\nSTATUS: done\nPROFILE: acme\n' 55
user "$proj/sess05-0000-0000.jsonl" $'[Subagent hand-back]\nthe template says\nMODE: gate | local | commit | ship\nSTATUS: green | red | done | blocked\n' 56
mkdir -p "$proj/sess06-0000-0000/subagents"
for i in 1 2 3; do assistant "$proj/sess06-0000-0000/subagents/agent-a.jsonl" "s$i" claude-fable-9; done
assistant "$proj/sess06-0000-0000/subagents/agent-a.jsonl" s3 claude-fable-9

out="$scratch/out"
"$S/scorecard.sh" "$runs" "$out" >/dev/null
field() { awk -F'\t' -v sid="$1" -v c="$2" 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == c) k = i; next } $4 == sid { print $k }' "$out/sessions.tsv"; }

[ "$(wc -l < "$out/sessions.tsv" | tr -d ' ')" = 16 ] || fail "case 1: 15 rows and a header, got $(wc -l < "$out/sessions.tsv")"
[ "$(field sess01-0 cost)" = 0.09 ] || fail "case 2: a repeated message id counts once, cost $(field sess01-0 cost)"
[ "$(field sess01-0 ctx_max_k)" = 101 ] || fail "case 3: ctx_max_k $(field sess01-0 ctx_max_k)"
[ "$(field sess13-0 transcript)" = no ] || fail "case 4: a row with no transcript says no"
[ "$(field sess03-0 guard_events)" = 1 ] || fail "case 5: guard_events $(field sess03-0 guard_events)"
[ "$(field sess03-0 events)" = "guard@01-02T10:30" ] || fail "case 5: events $(field sess03-0 events)"
[ "$(field sess04-0 final_gate)" = red ] || fail "case 6: final_gate $(field sess04-0 final_gate)"
[ "$(field sess05-0 gates)/$(field sess05-0 red_gates)/$(field sess05-0 final_gate)/$(field sess05-0 fix_rounds)" = 2/1/green/1 ] || fail "case 7: gates of sess05: $(field sess05-0 gates)/$(field sess05-0 red_gates)/$(field sess05-0 final_gate)/$(field sess05-0 fix_rounds)"
[ "$(field sess05-0 pr)" = "https://example.com/acme/shop/pull/7" ] || fail "case 8: pr $(field sess05-0 pr)"
[ "$(field sess05-0 max_gap_min)" = 41 ] || fail "case 9: max_gap_min $(field sess05-0 max_gap_min)"
[ "$(field sess06-0 cost_by_family)" = "fable=0.20,opus=0.09" ] || fail "case 10: cost_by_family $(field sess06-0 cost_by_family)"
[ "$(field sess06-0 cost_sub)/$(field sess06-0 sub_agents)" = 0.20/1 ] || fail "case 10: subagent cost $(field sess06-0 cost_sub)/$(field sess06-0 sub_agents)"

"$S/flag.sh" "$out" 2026-01-02 >/dev/null
pick() { awk -F'\t' -v sid="$1" '$4 == sid { print $6 ":" $7 }' "$out/flags.tsv"; }
[ "$(pick sess02-0)" = flag:turns ] || fail "case 11: user turns above the median: $(pick sess02-0)"
[ "$(pick sess03-0)" = flag:guard ] || fail "case 12: a guard event: $(pick sess03-0)"
[ "$(pick sess04-0)" = flag:gate ] || fail "case 13: a red final gate: $(pick sess04-0)"
[ "$(pick sess05-0)" = sample:- ] || [ "$(pick sess05-0)" = skip:- ] || fail "case 14: a red gate that ended green is clean: $(pick sess05-0)"
[ "$(pick sess06-0)" = flag:cost ] || fail "case 15: cost above the p90: $(pick sess06-0)"
[ "$(pick sess07-0)" = flag:short ] || fail "case 16: a short session: $(pick sess07-0)"
[ "$(pick sess13-0)" = missing:- ] || fail "case 17: no transcript: $(pick sess13-0)"
count() { awk -F'\t' -v st="$1" -v p="$2" 'NR > 1 && $1 == st && $6 == p' "$out/flags.tsv" | wc -l | tr -d ' '; }
[ "$(count exec flag)/$(count exec sample)/$(count exec skip)" = 5/2/5 ] || fail "case 18: exec picks $(count exec flag)/$(count exec sample)/$(count exec skip)"
[ "$(count plan sample)" = 2 ] || fail "case 19: a stage with two clean rows reads both"
cp "$out/flags.tsv" "$scratch/first.tsv"
"$S/flag.sh" "$out" 2026-01-02 >/dev/null
cmp -s "$out/flags.tsv" "$scratch/first.tsv" || fail "case 20: the same date gives the same sample"

stage() { awk -F'\t' -v st="$1" -v c="$2" 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == c) k = i; next } $4 == st { print $k }' "$out/stages.tsv"; }
[ "$(stage exec sessions_n)/$(stage exec no_transcript)/$(stage exec red_final_gates)/$(stage exec prs)/$(stage exec readers)" = 13/1/1/1/3 ] || fail "case 21: exec summary $(stage exec sessions_n)/$(stage exec no_transcript)/$(stage exec red_final_gates)/$(stage exec prs)/$(stage exec readers)"
[ "$(stage plan zero_user_turn_sessions)/$(stage plan handoffs)/$(stage plan readers)" = 2/2/1 ] || fail "case 22: plan summary"

card="$FLOW_LEARNING_DIR/scorecard.tsv"
printf 'date\told\theader\n' > "$card"
"$S/scorecard.sh" append "$out" exec=4 >/dev/null
[ "$(head -1 "$card")" = "$(head -1 "$out/stages.tsv")" ] || fail "case 23: a header-only card with other columns is replaced"
[ "$(wc -l < "$card" | tr -d ' ')" = 3 ] || fail "case 23: two stage rows, got $(wc -l < "$card")"
[ "$(awk -F'\t' '$4 == "exec" { print $17 }' "$card")/$(awk -F'\t' '$4 == "plan" { print $17 }' "$card")" = 4/na ] || fail "case 24: post_pr_defects"
"$S/scorecard.sh" append "$out" >/dev/null 2>&1
[ "$(wc -l < "$card" | tr -d ' ')" = 3 ] || fail "case 25: a second append of one run adds no row"

turns=$("$S/turns.sh" "$out" exec)
grep -q '^## sess02-0 acme 02$' <<<"$turns" || fail "case 26: turns names the session"
grep -q 'USER: please do it another way' <<<"$turns" || fail "case 26: turns holds the user line"
[ "$(grep -c 'ASSISTANT: working' <<<"$turns")" = 2 ] || fail "case 27: one assistant line before and one after"

mkdir -p "$FLOW_LEARNING_DIR/2026-01-02"
printf '# Digest\n\n- Stage exec.\n- Sessions covered:\n  aaaaaaa1 aaaaaaa2\n  aaaaaaa3\n- Read: aaaaaaa1\n- No transcript: bbbbbbb1\n\n## 1. Timeline\ncccccccc\n' > "$FLOW_LEARNING_DIR/2026-01-02/flow-exec.md"
[ "$("$S/covered-sids.sh" | tr '\n' ' ')" = "aaaaaaa1 aaaaaaa2 aaaaaaa3 " ] || fail "case 28: only the Sessions covered block counts: $("$S/covered-sids.sh" | tr '\n' ' ')"

echo "ok: 28 cases"
