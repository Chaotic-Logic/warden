#!/usr/bin/env bash
###
# warden SessionStart hook
# Standalone fallback. Injects the vibe-coding gate + minimalism bias ONLY
# when vizier is not enabled on this machine. On the owner's box
# core owns those rules, so this no-ops to avoid double injection. For anyone
# it's shared with (who won't have the private core),
# it makes the plugin behave sanely on its own.
#
# The safe-ops posture (confirm the target, read before you touch, never run
# anything destructive) is NOT injected here — it lives in the skills, so it
# only fires when there's actually a box in play, not on every session.
###

set -euo pipefail

[[ "${WARDEN_DISABLE:-0}" == "1" ]] && exit 0

# --- dedup guard: is vizier enabled here? ---
# Hooks can't natively see other plugins, so read enabledPlugins from settings.
is_vizier_enabled() {
    local settings="$HOME/.claude/settings.json"

    [[ -f "$settings" ]] || return 1

    if command -v jq &>/dev/null; then
        local hit
        hit=$(jq -r '(.enabledPlugins // {}) | to_entries[]
                     | select(.key | startswith("vizier@"))
                     | select(.value == true) | .key' "$settings" 2>/dev/null)
        [[ -n "$hit" ]] && return 0
    else
        # fallback: match "vizier@<marketplace>": true, spaces-tolerant
        grep -Eq '"vizier@[^"]*"[[:space:]]*:[[:space:]]*true' "$settings" && return 0
    fi
    return 1
}

# core present -> it owns the gate + minimalism, do nothing
is_vizier_enabled && exit 0

PROMPT_DIR="${CLAUDE_PLUGIN_ROOT}/prompts"
[[ -d "$PROMPT_DIR" ]] || exit 0

BODY=""
for name in vibe-gate minimalism; do
    f="${PROMPT_DIR}/${name}.md"
    [[ -f "$f" ]] && BODY+=$'\n\n'"$(<"$f")"
done
[[ -n "$BODY" ]] || exit 0

HEADER="# Standing rules — warden (standalone fallback)

vizier is not enabled here, so the systems plugin ships these itself: the vibe-coding gate and a minimalism bias. Install vizier and it takes these over; this stops firing."

python3 -c "
import json, sys
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'SessionStart',
        'additionalContext': sys.stdin.read()
    }
}))
" <<<"${HEADER}${BODY}"
