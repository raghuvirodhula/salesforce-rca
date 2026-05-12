# SessionStart hook: Re-inject WIP state on resume/compact.
# Matcher: "resume|compact" — only fires when resuming or after compaction.
# Outputs JSON with additionalContext if .claude/wip-context.md exists.
# Silent (no output) if the file doesn't exist.

$ErrorActionPreference = "Stop"

$wipFile = ".claude/wip-context.md"

if (-not (Test-Path $wipFile)) {
    exit 0
}

# Read the WIP file content
try {
    $content = Get-Content -Path $wipFile -Raw -Encoding UTF8
    $restoredContent = "## Restored WIP Context`n" + $content
    
    # Build JSON output with proper escaping
    $output = @{
        additionalContext = $restoredContent
    } | ConvertTo-Json -Compress
    
    Write-Output $output
} catch {
    exit 0
}

exit 0
