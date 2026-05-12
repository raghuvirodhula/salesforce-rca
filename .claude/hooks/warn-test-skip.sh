#!/usr/bin/env bash
# PostToolUse hook: Warn when adding skip/todo markers to test files.
# Non-blocking (exit 0 always) — surfaces a question, human decides.

set -euo pipefail

input=$(cat)

# Extract file_path and new_string from tool_input using Node.js
eval "$(echo "$input" | node -e "
const chunks = [];
process.stdin.on('data', c => chunks.push(c));
process.stdin.on('end', () => {
    try {
        const data = JSON.parse(chunks.join(''));
        const ti = data.tool_input || {};
        const fp = (ti.file_path || '').replace(/'/g, \"'\\\\''\" );
        const ns = (ti.new_string || '').replace(/'/g, \"'\\\\''\" );
        console.log(\"file_path='\" + fp + \"'\");
        console.log(\"new_string='\" + ns + \"'\");
    } catch(e) {
        console.log(\"file_path='' new_string=''\");
    }
});
" 2>/dev/null || echo "file_path='' new_string=''")"

# Only check files under __tests__/, test/, *.test.*, *.spec.*, or *Test.cls
case "$file_path" in
    *__tests__/*|*__tests__*|*/test/*|*.test.js|*.test.ts|*.spec.js|*.spec.ts|*Test.cls|*Test.cls-meta.xml) ;;
    *) exit 0 ;;
esac

# Check for Jest skip/todo patterns or Apex @IsTest(SeeAllData=true) anti-patterns
if echo "$new_string" | grep -qE 'test\.skip\(|it\.skip\(|describe\.skip\(|xit\(|xdescribe\(|test\.todo\(|@IsTest\(SeeAllData=true\)'; then
    echo "NOTE: Adding a skip, todo, or SeeAllData=true marker to a test file."
    echo "Is this intentional, or are we avoiding fixing a real failure?"
    echo "If temporary, add a comment with the reason and a tracking ticket number."
fi

exit 0
