#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/skills/review/reference/codex.sh"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export FLOW_HOME="$scratch/home"
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

user() { printf -- '---\n%s\n---\n' "$@" > "$FLOW_HOME/user.md"; }

user "reviews_dir: x"
p=$(pkg off)
expect_eq "off by default" "CODEX · off" "$(bash "$script" find "$p")"

user "codex_review: on"
p=$(pkg pr pr)
expect_eq "never in pr mode" "CODEX · off · pr mode" "$(bash "$script" find "$p")"

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

printf 'SETTLE · 1 contested · 1 changed\n' > "$p/codex/settle.md"
expect_eq "stats line" "CODEX · found 2 · kept 2 · unique 1 · contested 1 · changed 1" "$(bash "$script" stats "$p")"
expect_eq "trial header" "date	key	branch	sha	found	kept	unique	contested	changed" "$(head -1 "$FLOW_HOME/codex-trial.tsv")"
expect_has "trial row" "	demo	trial	01234567	2	2	1	1	1" "$(tail -1 "$FLOW_HOME/codex-trial.tsv")"

p=$(pkg noreply)
bash "$script" find "$p" > /dev/null
printf 'VERIFY · 2 in · 0 kept · 1 rejected · blocking no\nR1 | invented | app/e.rb:3 | all/F2 x — y\nBLOCKING: no\n' > "$p/verdict.md"
expect_eq "nothing to reply" "CODEX REPLY · 0 contested · 0 accepted · $p/codex/reply.md" "$(bash "$script" reply "$p")"

echo "codex.sh: $cases cases ok"
