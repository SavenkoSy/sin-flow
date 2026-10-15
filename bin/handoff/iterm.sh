#!/bin/bash
set -euo pipefail
line="cd $(printf %q "$FLOW_CWD") && $FLOW_PROMPT"
if [ "${1:-}" = --probe ]; then echo "osascript iTerm: new tab \"$FLOW_NAME\", write text: $line"; exit 0; fi
osascript - "$line" "$FLOW_NAME" <<'OSA'
on run argv
  set theLine to item 1 of argv
  set theName to item 2 of argv
  tell application "iTerm"
    if (count of windows) = 0 then
      set w to (create window with default profile)
      set s to current session of w
    else
      tell current window to set t to (create tab with default profile)
      set s to current session of t
    end if
    tell s
      set name to theName
      write text theLine
    end tell
  end tell
end run
OSA
