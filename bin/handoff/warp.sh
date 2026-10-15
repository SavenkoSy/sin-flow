#!/bin/bash
set -euo pipefail
name=$(printf '%s' "$FLOW_NAME" | tr -cs 'A-Za-z0-9' '_')
config="$HOME/.warp/tab_configs/$name.toml"
launcher="$HOME/.warp/sin_flow_launchers/$name.sh"
cmd=(open "warp://tab_config/$name")
if [ "${1:-}" = --probe ]; then echo "$config: directory $FLOW_CWD, runs $FLOW_PROMPT"; printf '%q ' "${cmd[@]}"; echo; exit 0; fi
mkdir -p "$(dirname "$config")" "$(dirname "$launcher")"
printf '%s\n' "$FLOW_PROMPT" > "$launcher"
cat > "$config" <<TOML
name = "$name"

[[panes]]
id = "main"
type = "terminal"
directory = "$FLOW_CWD"
commands = ['. $launcher']
TOML
"${cmd[@]}"
