#!/usr/bin/env bash
# SessionStart hook: Re-inject WIP state on resume/compact.
# Matcher: "resume|compact" — only fires when resuming or after compaction.
# Outputs JSON with additionalContext if .claude/wip-context.md exists.
# Silent (no output) if the file doesn't exist.

set -euo pipefail

WIP_FILE=".claude/wip-context.md"

if [ ! -f "$WIP_FILE" ]; then
    exit 0
fi

# Build JSON output in Node.js for reliable escaping
node -e '
const fs = require("fs");
try {
    const content = fs.readFileSync(".claude/wip-context.md", "utf8");
    const output = { additionalContext: "## Restored WIP Context\n" + content };
    console.log(JSON.stringify(output));
} catch (e) {
    process.exit(0);
}
'

exit 0
