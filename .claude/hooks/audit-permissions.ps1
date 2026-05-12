# SessionStart hook: Audit permissions in settings.local.json.
# Produces an informational report (exit 0, never blocks).
# Silent when no issues found (empty stdout = no output shown).

$ErrorActionPreference = "SilentlyContinue"

$settingsFile = ".claude/settings.local.json"
$reviewedFile = ".claude/permissions-reviewed.json"

# If no local settings file, nothing to audit
if (-not (Test-Path $settingsFile)) {
    exit 0
}

function Load-Json {
    param([string]$path)
    try {
        return Get-Content -Path $path -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Extract-Permissions {
    param($settings)
    $perms = @()
    $permissions = $settings.permissions
    if ($permissions) {
        foreach ($key in @("allow", "deny")) {
            $entries = $permissions.$key
            if ($entries) {
                foreach ($entry in $entries) {
                    $perms += @{rule = $entry; type = $key}
                }
            }
        }
    }
    return $perms
}

function Classify-Permission {
    param([string]$rule)
    $issues = @()
    $externalPatterns = @(
        "git push", "git commit", "glab mr", "glab issue",
        "docker rm", "docker stop", "kill ", "truncate",
        "rm -rf", "rm -r", "DROP TABLE", "DELETE FROM"
    )
    
    foreach ($pattern in $externalPatterns) {
        if ($rule.Contains($pattern)) {
            $issues += "modifies external state ($pattern)"
            break
        }
    }
    
    if (($rule.Contains('"') -or $rule.Contains("'")) -and $rule.Length -gt 100) {
        $issues += "looks like a one-time approval (very specific)"
    }
    
    return $issues
}

function Find-ConsolidationOpportunities {
    param($permissions, $reviewedPatterns)
    $groups = @{}
    
    foreach ($p in $permissions) {
        if ($p.rule -match '^(\w+(?:\([^\s)]+)?)') {
            $prefix = $matches[1]
        } else {
            $prefix = $p.rule
        }
        
        if (-not $groups.ContainsKey($prefix)) {
            $groups[$prefix] = @()
        }
        $groups[$prefix] += $p.rule
    }
    
    $suggestions = @()
    foreach ($prefix in $groups.Keys) {
        $rules = $groups[$prefix]
        if ($rules.Count -ge 3) {
            $allReviewed = $true
            foreach ($rule in $rules) {
                $isReviewed = $reviewedPatterns -contains $rule
                if (-not $isReviewed) {
                    foreach ($rp in $reviewedPatterns) {
                        if ($rp.EndsWith(":*") -and $rule.StartsWith($rp.Replace(":*", ""))) {
                            $isReviewed = $true
                            break
                        }
                    }
                }
                if (-not $isReviewed) {
                    $allReviewed = $false
                    break
                }
            }
            if (-not $allReviewed) {
                $suggestions += "  $($rules.Count) entries starting with '$prefix' - consider consolidating"
            }
        }
    }
    
    return $suggestions
}

$settings = Load-Json $settingsFile
if (-not $settings) { exit 0 }

$reviewedData = Load-Json $reviewedFile
$reviewedPatterns = @()
if ($reviewedData -and $reviewedData.reviewed) {
    foreach ($entry in $reviewedData.reviewed) {
        if ($entry.pattern) {
            $reviewedPatterns += $entry.pattern
        }
    }
}

$permissions = Extract-Permissions $settings
if ($permissions.Count -eq 0) { exit 0 }

$unreviewed = @()
$risky = @()
$staleCandidates = @()
$consolidation = Find-ConsolidationOpportunities $permissions $reviewedPatterns

foreach ($p in $permissions) {
    $rule = $p.rule
    $issues = Classify-Permission $rule
    
    $isReviewed = $reviewedPatterns -contains $rule
    if (-not $isReviewed) {
        foreach ($rp in $reviewedPatterns) {
            if ($rp.EndsWith(":*") -and $rule.StartsWith($rp.Replace(":*", ""))) {
                $isReviewed = $true
                break
            }
        }
    }
    
    if (-not $isReviewed) {
        $unreviewed += $rule
    }
    
    foreach ($issue in $issues) {
        if ($issue.Contains("external state")) {
            $risky += @($rule, $issue)
        }
        if ($issue.Contains("one-time")) {
            $staleCandidates += $rule
        }
    }
}

if ($unreviewed.Count -eq 0 -and $risky.Count -eq 0 -and $staleCandidates.Count -eq 0 -and $consolidation.Count -eq 0) {
    exit 0
}

# Generate reviewed file template if it does not exist
if (-not $reviewedData) {
    try {
        $template = @{
            reviewed = @()
            last_audit = (Get-Date).ToString("yyyy-MM-dd")
            _comment = "Track reviewed permissions. Add entries as you review them."
        }
        $template | ConvertTo-Json | Out-File -FilePath $reviewedFile -Encoding UTF8
    } catch {
        # Silently fail if unable to create file
    }
}

# Build audit report as JSON output for Claude
$report = "--- Permissions Audit ---`n`n"

if ($unreviewed.Count -gt 0) {
    $report += "UNREVIEWED PERMISSIONS ($($unreviewed.Count)):`n"
    foreach ($r in $unreviewed) {
        $issues = Classify-Permission $r
        $risk = if ($issues.Count -gt 0) { " ⚠ $($issues[0])" } else { "" }
        $report += "  - $r$risk`n"
    }
    $report += "`n"
}

if ($staleCandidates.Count -gt 0) {
    $report += "Possible stale one-offs ($($staleCandidates.Count)) - consider removing:`n"
    foreach ($r in $staleCandidates | Select-Object -First 5) {
        $report += "  - $($r.Substring(0, [Math]::Min(80, $r.Length)))...`n"
    }
    $report += "`n"
}

if ($consolidation.Count -gt 0) {
    $report += "Consolidation opportunities:`n"
    foreach ($s in $consolidation) {
        $report += "$s`n"
    }
    $report += "`n"
}

if ($unreviewed.Count -gt 0) {
    $report += "ACTION REQUIRED: Run the interactive permissions review before proceeding.`n"
    $report += "See .claude/rules/permissions-review.md for the review protocol."
}

# Output as JSON for Claude
$output = @{
    additionalContext = $report
} | ConvertTo-Json -Compress

Write-Output $output

exit 0
