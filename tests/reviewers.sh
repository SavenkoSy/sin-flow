#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/skills/review/reference/reviewers.sh"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export FLOW_HOME="$scratch/home" CLAUDE_CONFIG_DIR="$scratch/home"
unset $(compgen -e | grep '^CLAUDE_PLUGIN_OPTION_' || true)
mkdir -p "$FLOW_HOME" "$scratch/bin" "$scratch/tree"
git -C "$scratch/tree" init -q -b trial
cases=0

fail() { echo "FAIL: $*" >&2; exit 1; }

expect_eq() {
  cases=$((cases + 1))
  [ "$2" = "$3" ] || fail "$1: want [$2], got [$3]"
}

expect_has() {
  cases=$((cases + 1))
  case "$3" in *"$2"*) ;; *) fail "$1: want substring [$2], got [$3]" ;; esac
}

cat > "$scratch/bin/codex" <<'EOF'
#!/usr/bin/env bash
[ "$1" = login ] && { [ "${FAKE:-}" = nologin ] && exit 1; exit 0; }
out=
prev=
resume=no
for a in "$@"; do
  [ "$prev" = -o ] && out=$a
  [ "$a" = resume ] && resume=yes
  prev=$a
done
case "${FAKE:-}" in
  limit) echo "ERROR: You've hit your usage limit." >&2; exit 1 ;;
  badjson) echo "not json" > "$out"; exit 0 ;;
esac
if [ "$resume" = yes ]; then
  cat > "$out" <<'JSON'
{"replies":[
 {"row":"R1","stance":"contest","argument":"The caller passes nil.","evidence":"app/a.rb:12 call(nil)"},
 {"row":"K1","stance":"accept","argument":"ok","evidence":""},
 {"row":"K2","stance":"contest","argument":"No quote here.","evidence":"trust me"},
 {"row":"R9","stance":"contest","argument":"Unknown row.","evidence":"app/b.rb:3 x"}
]}
JSON
else
  echo "session id: sess-1" >&2
  cat > "$out" <<'JSON'
{"findings":[
 {"file":"app/a.rb","line":12,"checklists":["paths"],"claim":"Nil  reaches\nthe call.","trigger":"job perform","evidence":"app/a.rb:12 call(x)","breaks":"The job fails."},
 {"file":"app/b.rb","line":3,"checklists":[],"claim":"Second.","trigger":"none found","evidence":"app/b.rb:3 y","breaks":"Wrong count."}
]}
JSON
fi
EOF
chmod +x "$scratch/bin/codex"
export PATH="$scratch/bin:$PATH"

pkg() {
  local dir="$scratch/pkg-$1"
  rm -rf "$dir"
  mkdir -p "$dir"
  printf '%s\n' "MODE=${2:-exec}" "KEY=demo" "SHA=0123456789abcdef" "BASE=fedcba98" "TREE=$scratch/tree" \
    "STACK=js" "TEAM=no" > "$dir/manifest.env"
  echo "$dir"
}

user() {
  local o='{}'
  while [ $# -gt 0 ]; do o=$(jq -c --arg k "$1" --arg v "$2" '. + {($k): $v}' <<< "$o"); shift 2; done
  jq -n --argjson o "$o" '{pluginConfigs: {"sin-flow@test": {options: $o}}}' > "$CLAUDE_CONFIG_DIR/settings.json"
}

user reviews_dir x
p=$(pkg off)
expect_eq "off by default" "REVIEWERS · off" "$(bash "$script" find "$p")"

user extra_reviewers codex
p=$(pkg pr pr)
expect_eq "pr mode without a model" "CODEX · off · pr mode, no model for codex_model_pr" "$(bash "$script" find "$p")"

p=$(pkg nologin)
expect_eq "no login" "CODEX · skipped · not logged in" "$(FAKE=nologin bash "$script" find "$p")"
expect_eq "no login recorded" "lens codex skipped: not logged in" "$(cat "$p/failed.txt")"

p=$(pkg limit)
expect_eq "usage limit" "CODEX · skipped · usage limit" "$(FAKE=limit bash "$script" find "$p")"

p=$(pkg badjson)
expect_eq "bad answer" "CODEX · skipped · no JSON answer" "$(FAKE=badjson bash "$script" find "$p")"
[ -e "$p/findings/codex.md" ] && fail "bad answer: findings file written"

p=$(PATH=/usr/bin:/bin pkg missing)
expect_eq "not installed" "CODEX · skipped · not installed" "$(PATH=/usr/bin:/bin:$(dirname "$(command -v jq)") bash "$script" find "$p")"

p=$(pkg ok)
expect_eq "find line" "LENS codex · 2 findings · $p/findings/codex.md" "$(bash "$script" find "$p")"
expect_eq "finder header" "LENS: codex · 2 findings" "$(head -1 "$p/findings/codex.md")"
expect_eq "row one" "F1 | app/a.rb:12 | [paths] Nil reaches the call." "$(sed -n 2p "$p/findings/codex.md")"
expect_has "empty checklist tag" "F2 | app/b.rb:3 | [codex] Second." "$(cat "$p/findings/codex.md")"
expect_eq "declined line" "DECLINED: none" "$(tail -1 "$p/findings/codex.md")"
expect_eq "session saved" "sess-1" "$(cat "$p/codex/session")"

cat > "$p/verdict.md" <<'EOF'
VERIFY · 25 in · 2 kept · 1 rejected · blocking no
K1 | med | reproduces | app/a.rb:12 | Nil reaches the call.
  from: codex/F1, all/F3
  trigger: x
K2 | low | possible | app/c.rb:4 | Only codex saw this.
  from: codex/F2
  trigger: y
K3 | low | possible | app/d.rb:5 | Only claude saw this.
  from: all/F1
R1 | invented | app/b.rb:3 | codex/F9 second — guard at app/b.rb:1
R2 | invented | app/e.rb:3 | all/F2 other — guard at app/e.rb:1
BLOCKING: no — no high
EOF
expect_eq "reply line" "CODEX REPLY · 1 contested · 1 accepted · $p/codex/reply.md" "$(bash "$script" reply "$p")"
expect_eq "reply keeps quoted contest only" "R1 | contest | The caller passes nil." "$(sed -n 2p "$p/codex/reply.md")"
expect_eq "reply size" "3" "$(grep -c . "$p/codex/reply.md")"

printf 'SETTLE · 1 contested · 1 changed\nR1 → K4 | changed | codex | the caller passes nil at app/a.rb:12\n' > "$p/settle.md"
expect_eq "stats line" "CODEX · found 2 · kept 2 · unique 1 · contested 1 · changed 1" "$(bash "$script" stats "$p")"
expect_eq "trial header" "date	key	branch	sha	found	kept	unique	contested	changed" "$(head -1 "$FLOW_HOME/codex-trial.tsv")"
expect_has "trial row" "	demo	trial	01234567	2	2	1	1	1" "$(tail -1 "$FLOW_HOME/codex-trial.tsv")"

p=$(pkg noreply)
bash "$script" find "$p" > /dev/null
printf 'VERIFY · 2 in · 0 kept · 1 rejected · blocking no\nR1 | invented | app/e.rb:3 | all/F2 x — y\nBLOCKING: no\n' > "$p/verdict.md"
expect_eq "nothing to reply" "CODEX REPLY · 0 contested · 0 accepted · $p/codex/reply.md" "$(bash "$script" reply "$p")"

user extra_reviewers ""
expect_eq "empty list" "REVIEWERS · off" "$(bash "$script" find "$(pkg off2)")"

user extra_reviewers codex
p=$(pkg named)
expect_eq "extra codex" "LENS codex · 2 findings · $p/findings/codex.md" "$(bash "$script" find "$p")"

mkdir -p "$scratch/user" "$scratch/other"
cat > "$scratch/user/second.sh" <<'EOF'
#!/usr/bin/env bash
[ "$PWD" = "$(. "$2/manifest.env"; echo "$TREE")" ] || exit 9
case "${FAKE:-}:$3" in
  fail:second) echo "boom" >&2; exit 3 ;;
  silent:*) exit 0 ;;
  prose:*) echo "Looks fine to me."; exit 0 ;;
  loose:*) [ "$1" = reply ] && { printf 'K1 | contest | Quoted.\n  evidence: app/a.rb:1 x\nK1 | contest | No quote.\n  evidence: trust me\nK9 | contest | Unknown.\n  evidence: app/b.rb:2 y\n'; exit 0; } ;;
esac
case "$1" in
  find) printf 'F1 | app/a.rb:12 | [paths] Own %s.\n  trigger: x\n  evidence: y\n  breaks: z\n' "$3" ;;
  reply) printf 'K1 | contest | No.\n  evidence: app/a.rb:1 x\n' ;;
esac
EOF
chmod +x "$scratch/user/second.sh"
cp "$scratch/user/second.sh" "$scratch/user/third.sh"
cp "$scratch/user/second.sh" "$scratch/other/second.sh"
cp "$root/examples/reviewer.sh.example" "$scratch/user/example.sh"

user extra_reviewers "$scratch/user/second.sh $scratch/user/third.sh"
p=$(pkg two)
expect_eq "two scripts" "LENS second · 1 findings · $p/findings/second.md
LENS third · 1 findings · $p/findings/third.md" "$(bash "$script" find "$p")"
expect_eq "script file" "LENS: third · 1 findings" "$(head -1 "$p/findings/third.md")"
expect_eq "script declined line" "DECLINED: none" "$(tail -1 "$p/findings/third.md")"
printf 'VERIFY · 2 in · 1 kept · 0 rejected · blocking no\nK1 | med | reproduces | app/a.rb:12 | Own.\n  from: second/F1, third/F1\nBLOCKING: no\n' > "$p/verdict.md"
expect_eq "two replies" "SECOND REPLY · 1 contested · 0 accepted · $p/second/reply.md
THIRD REPLY · 1 contested · 0 accepted · $p/third/reply.md" "$(bash "$script" reply "$p")"
printf 'SETTLE · 1 contested · 1 changed\nK1 → R1 | changed | third | guard at app/a.rb:1\n' > "$p/settle.md"
rows=$(wc -l < "$FLOW_HOME/codex-trial.tsv")
expect_eq "two stats" "SECOND · found 1 · kept 1 · unique 0 · contested 1 · changed 0
THIRD · found 1 · kept 1 · unique 0 · contested 1 · changed 1" "$(bash "$script" stats "$p")"
expect_eq "scripts keep the codex trial" "$rows" "$(wc -l < "$FLOW_HOME/codex-trial.tsv")"
p=$(pkg silent)
bash "$script" find "$p" > /dev/null
printf 'VERIFY · 1 in · 1 kept · 0 rejected · blocking no\nK1 | med | reproduces | app/a.rb:12 | Own.\n  from: second/F1\nBLOCKING: no\n' > "$p/verdict.md"
expect_eq "silent reply accepts" "SECOND REPLY · 0 contested · 1 accepted · $p/second/reply.md" "$(FAKE=silent bash "$script" reply "$p" | head -1)"

p=$(pkg loose)
bash "$script" find "$p" > /dev/null
printf 'VERIFY · 1 in · 1 kept · 0 rejected · blocking no\nK1 | med | reproduces | app/a.rb:12 | Own.\n  from: second/F1\nBLOCKING: no\n' > "$p/verdict.md"
expect_eq "script contests filtered" "SECOND REPLY · 1 contested · 0 accepted · $p/second/reply.md" "$(FAKE=loose bash "$script" reply "$p" | head -1)"
expect_eq "script contest kept" "K1 | contest | Quoted." "$(sed -n 2p "$p/second/reply.md")"
p=$(pkg prose)
expect_eq "prose is skipped" "SECOND · skipped · output not in finder format: Looks fine to me." "$(FAKE=prose bash "$script" find "$p" | head -1)"
expect_has "prose recorded" "lens second skipped: output not in finder format: Looks fine to me." "$(cat "$p/failed.txt")"

user extra_reviewers off
expect_eq "off is empty" "REVIEWERS · off" "$(bash "$script" find "$(pkg offword)")"

cat > "$scratch/bin/orca" <<'EOF'
#!/usr/bin/env bash
[ "$1" = status ] && { echo '{"result":{"runtime":{"reachable":true}}}'; exit 0; }
prev=
for a in "$@"; do [ "$prev" = --comment ] && printf '%s\n' "$a" > "$ORCA_LOG"; prev=$a; done
EOF
chmod +x "$scratch/bin/orca"
user extra_reviewers "$scratch/user/second.sh $scratch/user/third.sh" reviewer_watch orca
p=$(pkg orca)
ORCA_LOG="$scratch/orca.log" bash "$script" find "$p" > /dev/null
expect_has "orca card keeps second" "second: 1 findings" "$(cat "$scratch/orca.log")"
expect_has "orca card keeps third" "third: 1 findings" "$(cat "$scratch/orca.log")"
rm -f "$scratch/bin/orca"

user extra_reviewers "codex $scratch/user/second.sh"
p=$(pkg mixed)
expect_eq "codex and a script" "LENS codex · 2 findings · $p/findings/codex.md
LENS second · 1 findings · $p/findings/second.md" "$(bash "$script" find "$p")"

user extra_reviewers "$scratch/user/second.sh $scratch/user/third.sh"
p=$(pkg onefails)
expect_eq "one fails, one runs" "SECOND · skipped · exit 3
LENS third · 1 findings · $p/findings/third.md" "$(FAKE=fail bash "$script" find "$p")"
expect_eq "failure recorded" "lens second skipped: exit 3" "$(cat "$p/failed.txt")"

user extra_reviewers "$scratch/user/second.sh $scratch/other/second.sh"
p=$(pkg dup)
expect_eq "duplicate name" "LENS second · 1 findings · $p/findings/second.md
SECOND · skipped · duplicate name second: $scratch/other/second.sh" "$(bash "$script" find "$p")"
expect_eq "duplicate recorded" "lens second skipped: duplicate name second: $scratch/other/second.sh" "$(cat "$p/failed.txt")"

cp "$scratch/user/second.sh" "$scratch/user/verify.sh"
user extra_reviewers "$scratch/user/verify.sh gemini"
p=$(pkg reserved)
expect_eq "flow name and bad entry" "VERIFY · skipped · the name verify belongs to the flow: $scratch/user/verify.sh
GEMINI · skipped · 'gemini' is not codex or a path" "$(bash "$script" find "$p")"

user extra_reviewers "$scratch/user/second.sh"
expect_eq "script in pr mode" "SECOND · off · pr mode runs only Codex" "$(bash "$script" find "$(pkg scriptpr pr)")"

user extra_reviewers "~/second.sh"
ln -s "$scratch/user/second.sh" "$scratch/second.sh"
p=$(pkg tilde)
expect_eq "tilde path" "LENS second · 1 findings · $p/findings/second.md" "$(HOME="$scratch" bash "$script" find "$p")"

user extra_reviewers "$scratch/user/missing.sh $scratch/user/third.sh"
p=$(pkg missing-own)
expect_eq "missing path" "MISSING · skipped · $scratch/user/missing.sh is not an executable file
LENS third · 1 findings · $p/findings/third.md" "$(bash "$script" find "$p")"

user extra_reviewers "$scratch/user/example.sh"
p=$(pkg example)
expect_eq "example find" "LENS example · 0 findings · $p/findings/example.md" "$(bash "$script" find "$p")"

echo "reviewers.sh: $cases cases ok"
