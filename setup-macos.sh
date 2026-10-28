#!/bin/bash
# Build the MCP bridge and register it with Claude Code and/or Claude Desktop.
# Usage: ./setup-macos.sh [--code] [--desktop]   (default: both, where installed)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER="$HERE/pcsx2-mcp-server/dist/index.js"
DO_CODE=0; DO_DESKTOP=0
for a in "$@"; do
	case "$a" in
		--code) DO_CODE=1 ;;
		--desktop) DO_DESKTOP=1 ;;
		*) echo "unknown option $a"; exit 1 ;;
	esac
done
[ $DO_CODE = 0 ] && [ $DO_DESKTOP = 0 ] && DO_CODE=1 && DO_DESKTOP=1

command -v node > /dev/null || { echo "Node.js >= 18 required (brew install node)"; exit 1; }
(cd "$HERE/pcsx2-mcp-server" && npm ci && npm run build)

if [ $DO_CODE = 1 ]; then
	if command -v claude > /dev/null; then
		# Re-add so a moved checkout updates the path.
		claude mcp remove --scope user pcsx2 > /dev/null 2>&1 || true
		claude mcp add --scope user pcsx2 -- node "$SERVER" && echo "Claude Code: added 'pcsx2'"
	else
		echo "Claude Code CLI not found; skipped"
	fi
fi

if [ $DO_DESKTOP = 1 ]; then
	CFG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
	if [ -d "$(dirname "$CFG")" ]; then
		# Keep the first backup: later runs must not overwrite the original config.
		[ -f "$CFG" ] && [ ! -f "$CFG.bak" ] && cp "$CFG" "$CFG.bak"
		python3 - "$CFG" "$SERVER" <<'EOF'
import json, os, sys
cfg, server = sys.argv[1], sys.argv[2]
data = json.load(open(cfg)) if os.path.exists(cfg) else {}
data.setdefault("mcpServers", {})["pcsx2"] = {"command": "node", "args": [server]}
json.dump(data, open(cfg, "w"), indent=2)
EOF
		echo "Claude Desktop: added 'pcsx2' (backup: $CFG.bak); restart Claude Desktop"
	else
		echo "Claude Desktop not found; skipped"
	fi
fi
