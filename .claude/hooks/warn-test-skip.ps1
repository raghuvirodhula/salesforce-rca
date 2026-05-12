# PostToolUse hook: Warn when adding skip/todo markers to test files.
# Non-blocking (always exits successfully) — surfaces a question, human decides.

$ErrorActionPreference = "Stop"

# Read input from stdin
$input = [Console]::In.ReadToEnd()

# Extract file_path and new_string from tool_input using PowerShell
try {
    $data = $input | ConvertFrom-Json
    $toolInput = $data.tool_input
    $filePath = $toolInput.file_path
    $newString = $toolInput.new_string
} catch {
    $filePath = ""
    $newString = ""
}

# Only check test files
$isTestFile = $false
$testPatterns = @(
    "*__tests__/*", "*__tests__*", "*/test/*", 
    "*.test.js", "*.test.ts", "*.spec.js", "*.spec.ts",
    "*Test.cls", "*Test.cls-meta.xml"
)

foreach ($pattern in $testPatterns) {
    if ($filePath -like $pattern) {
        $isTestFile = $true
        break
    }
}

if (-not $isTestFile) {
    exit 0
}

# Check for Jest skip/todo patterns or Apex @IsTest(SeeAllData=true) anti-patterns
$skipPatterns = @(
    'test\.skip\(',
    'it\.skip\(',
    'describe\.skip\(',
    'xit\(',
    'xdescribe\(',
    'test\.todo\(',
    '@IsTest\(SeeAllData=true\)'
)

$hasSkipPattern = $false
foreach ($pattern in $skipPatterns) {
    if ($newString -match $pattern) {
        $hasSkipPattern = $true
        break
    }
}

if ($hasSkipPattern) {
    Write-Host "NOTE: Adding a skip, todo, or SeeAllData=true marker to a test file."
    Write-Host "Is this intentional, or are we avoiding fixing a real failure?"
    Write-Host "If temporary, add a comment with the reason and a tracking ticket number."
}

exit 0
