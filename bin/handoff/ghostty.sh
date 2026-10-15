#!/bin/bash
set -euo pipefail
if [ "${1:-}" = --probe ]; then echo "osascript Ghostty: new tab in $FLOW_CWD, input: $FLOW_PROMPT"; exit 0; fi
osascript - "$FLOW_CWD" "$FLOW_PROMPT" <<'OSA'
on run argv
  set theDir to item 1 of argv
  set theLine to item 2 of argv
  tell application "Ghostty"
    set cfg to new surface configuration
    set initial working directory of cfg to theDir
    set initial input of cfg to theLine & linefeed
    if (count of windows) = 0 then
      new window with configuration cfg
    else
      new tab in front window with configuration cfg
    end if
  end tell
end run
OSA
