#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
[ $# -eq 1 ] && [ -d "$1" ] || { echo "usage: make-apply.sh <learning dir>/<date>" >&2; exit 2; }
day=$(cd "$1" && pwd -P)
date=$(basename "$day")
learning=$(dirname "$day")
plugin_root=$(cd "${CLAUDE_PLUGIN_ROOT:-$here/../../..}" && pwd -P)
user_root="${FLOW_HOME:-$HOME/.claude/sin-flow}"
mkdir -p "$user_root"
user_root=$(cd "$user_root" && pwd -P)
apply="$day/apply"
rm -rf "$apply"
mkdir -p "$apply"
sha() { if [ -e "$1" ]; then shasum -a 256 "$1" | cut -d' ' -f1; else echo absent; fi; }

list="$apply/.copies"
: > "$list"
for space in "$day"/*/proposed; do
  [ -d "$space" ] || continue
  stage=$(basename "$(dirname "$space")")
  [ "$stage" = apply ] && continue
  for root in plugin user; do
    [ -d "$space/$root" ] || continue
    (cd "$space/$root" && find . -type f | sed 's#^\./##') | while IFS= read -r path; do
      printf '%s\t%s\t%s\t%s\n' "$root" "$path" "$stage" "$space/$root/$path"
    done
  done
done | sort -t$'\t' -k1,1 -k2,2 -k3,3 > "$list"

printf 'layer\troot\tpath\ttarget\tsha256\tproposed\tstages\n' > "$apply/targets.tsv"
: > "$apply/patches.diff"
cut -f1,2 "$list" | uniq | while IFS=$'\t' read -r root path; do
  if [ "$root" = plugin ]; then target="$plugin_root/$path"; layer=plugin; else target="$user_root/$path"; layer=user; fi
  case "$root/$path" in user/profiles/*) layer=profile ;; esac
  final="$apply/proposed/$root/$path"
  mkdir -p "$(dirname "$final")"
  stages=$(awk -F'\t' -v r="$root" -v p="$path" '$1 == r && $2 == p { printf "%s%s", sep, $3; sep = "," }' "$list")
  merged=$(awk -F'\t' -v r="$root" -v p="$path" '$1 == r && $2 == p && $3 == "merged" { print $4 }' "$list")
  if [ -n "$merged" ]; then
    cp -p "$merged" "$final"
  else
    first=1
    awk -F'\t' -v r="$root" -v p="$path" '$1 == r && $2 == p { print $4 }' "$list" | while IFS= read -r copy; do
      if [ "$first" = 1 ]; then cp -p "$copy" "$final"; first=0; continue; fi
      base="$target"
      [ -e "$base" ] || base=/dev/null
      if ! git merge-file -q "$final" "$base" "$copy"; then echo "$root/$path" >> "$apply/conflicts.txt"; fi
    done
  fi
  if [ -e "$target" ] && cmp -s "$final" "$target"; then rm -f "$final"; continue; fi
  want_sha=$(awk -F'\t' -v r="$root" -v p="$path" '$1 == r && $2 == p { v = $3 } END { if (v != "") print v }' "$day"/*/proposed/base.tsv 2>/dev/null)
  [ -n "$want_sha" ] || want_sha=$(sha "$target")
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$layer" "$root" "$path" "$target" "$want_sha" "$final" "$stages" >> "$apply/targets.tsv"
  if [ -e "$target" ]; then diff -u "$target" "$final" >> "$apply/patches.diff"; else diff -u /dev/null "$final" >> "$apply/patches.diff"; fi
done
rm -f "$list"

if [ -s "$apply/conflicts.txt" ]; then
  echo "two stages changed the same lines. Write the merged copy to $day/merged/proposed/<root>/<path> and run again:" >&2
  sort -u "$apply/conflicts.txt" >&2
  exit 1
fi

write_script() {
  cat > "$apply/$1" <<SCRIPT
#!/usr/bin/env bash
set -uo pipefail
targets='$apply/targets.tsv'
backups='$learning/backups/$date'
rollback='$apply/rollback'
checkout='$plugin_root'
layers='$2'
SCRIPT
  cat >> "$apply/$1" <<'SCRIPT'
sha() { if [ -e "$1" ]; then shasum -a 256 "$1" | cut -d' ' -f1; else echo absent; fi; }
rows() { awk -F'\t' -v layers="$layers" 'NR > 1 && index(" " layers " ", " " $1 " ")' "$targets"; }
restore() {
  rows | while IFS=$'\t' read -r layer root path target want proposed stages; do
    if [ -e "$rollback/$root/$path" ]; then cp -p "$rollback/$root/$path" "$target"; elif [ "$want" = absent ]; then rm -f "$target"; fi
  done
}
abort() { echo "$1: every target restored"; restore; exit 4; }
[ -n "$(rows)" ] || { echo "no target for: $layers"; exit 0; }
stale=0
while IFS=$'\t' read -r layer root path target want proposed stages; do
  [ "$(sha "$target")" = "$want" ] || { echo "changed since the proposal, nothing applied: $target"; stale=1; }
done < <(rows)
[ "$stale" = 0 ] || exit 3
while IFS=$'\t' read -r layer root path target want proposed stages; do
  if [ "$want" != absent ]; then
    mkdir -p "$(dirname "$backups/$path")" "$(dirname "$rollback/$root/$path")" || abort "backup folder failed: $target"
    [ -e "$backups/$path" ] || cp -p "$target" "$backups/$path" || abort "backup failed: $target"
    cp -p "$target" "$rollback/$root/$path.part" && cmp -s "$target" "$rollback/$root/$path.part" && mv "$rollback/$root/$path.part" "$rollback/$root/$path" || { rm -f "$rollback/$root/$path.part"; abort "rollback copy failed: $target"; }
  fi
  mkdir -p "$(dirname "$target")"
  if cp -p "$proposed" "$target.new" && mv "$target.new" "$target" && cmp -s "$proposed" "$target"; then
    echo "applied $target"
  else
    echo "apply failed, every target restored: $target"
    restore
    exit 4
  fi
done < <(rows)
case " $layers " in
  *" plugin "*)
    if ! (cd "$checkout" && bash scripts/check-layers.sh); then
      echo "check-layers.sh failed, every target restored"
      restore
      exit 5
    fi
    ;;
esac
SCRIPT
  chmod +x "$apply/$1"
}
write_script apply-user.sh 'user profile'
write_script apply-plugin.sh plugin
cat "$apply/targets.tsv"
