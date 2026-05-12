#!/usr/bin/env bash
# SessionStart hook: Audit permissions in settings.local.json.
# Produces an informational report (exit 0, never blocks).
# Silent when no issues found (empty stdout = no output shown).

set -euo pipefail

SETTINGS_FILE=".claude/settings.local.json"
REVIEWED_FILE=".claude/permissions-reviewed.json"

# If no local settings file, nothing to audit
if [ ! -f "$SETTINGS_FILE" ]; then
    exit 0
fi

# Run the audit via Node.js for JSON parsing
node -e '
const fs = require("fs");

const SETTINGS_FILE = ".claude/settings.local.json";
const REVIEWED_FILE = ".claude/permissions-reviewed.json";

function loadJson(path) {
    try {
        return JSON.parse(fs.readFileSync(path, "utf8"));
    } catch (e) {
        return null;
    }
}

function extractPermissions(settings) {
    const perms = [];
    const p = settings.permissions || {};
    for (const key of ["allow", "deny"]) {
        for (const entry of (p[key] || [])) {
            perms.push({ rule: entry, type: key });
        }
    }
    return perms;
}

function classifyPermission(rule) {
    const issues = [];
    const externalPatterns = [
        "git push", "git commit", "glab mr", "glab issue",
        "docker rm", "docker stop", "kill ", "truncate",
        "rm -rf", "rm -r", "DROP TABLE", "DELETE FROM",
    ];
    for (const pattern of externalPatterns) {
        if (rule.includes(pattern)) {
            issues.push(`modifies external state (${pattern})`);
            break;
        }
    }
    if ((rule.includes("\"") || rule.includes("'"'"'")) && rule.length > 100) {
        issues.push("looks like a one-time approval (very specific)");
    }
    return issues;
}

function findConsolidationOpportunities(permissions, reviewedPatterns) {
    const groups = {};
    for (const p of permissions) {
        const match = p.rule.match(/^(\w+(?:\([^\s)]+)?)/);
        const prefix = match ? match[1] : p.rule;
        if (!groups[prefix]) groups[prefix] = [];
        groups[prefix].push(p.rule);
    }
    const suggestions = [];
    for (const [prefix, rules] of Object.entries(groups)) {
        if (rules.length >= 3) {
            const allReviewed = rules.every(rule =>
                reviewedPatterns.has(rule) ||
                [...reviewedPatterns].some(rp => rp.endsWith(":*") && rule.startsWith(rp.replace(":*", "")))
            );
            if (!allReviewed) {
                suggestions.push(`  ${rules.length} entries starting with '"'"'${prefix}'"'"' — consider consolidating`);
            }
        }
    }
    return suggestions;
}

const settings = loadJson(SETTINGS_FILE);
if (!settings) process.exit(0);

const reviewedData = loadJson(REVIEWED_FILE);
const reviewedPatterns = new Set();
if (reviewedData) {
    for (const entry of (reviewedData.reviewed || [])) {
        if (entry.pattern) reviewedPatterns.add(entry.pattern);
    }
}

const permissions = extractPermissions(settings);
if (permissions.length === 0) process.exit(0);

const unreviewed = [];
const risky = [];
const staleCandidates = [];
const consolidation = findConsolidationOpportunities(permissions, reviewedPatterns);

for (const p of permissions) {
    const rule = p.rule;
    const issues = classifyPermission(rule);
    const isReviewed = reviewedPatterns.has(rule) ||
        [...reviewedPatterns].some(rp => rp.endsWith(":*") && rule.startsWith(rp.replace(":*", "")));

    if (!isReviewed) unreviewed.push(rule);

    for (const issue of issues) {
        if (issue.includes("external state")) risky.push([rule, issue]);
        if (issue.includes("one-time")) staleCandidates.push(rule);
    }
}

if (unreviewed.length === 0 && risky.length === 0 && staleCandidates.length === 0 && consolidation.length === 0) {
    process.exit(0);
}

console.log("--- Permissions Audit ---");
console.log();

if (unreviewed.length > 0) {
    console.log(`UNREVIEWED PERMISSIONS (${unreviewed.length}):`);
    for (const r of unreviewed) {
        const issues = classifyPermission(r);
        const risk = issues.length > 0 ? ` ⚠ ${issues[0]}` : "";
        console.log(`  - ${r}${risk}`);
    }
    console.log();
}

if (staleCandidates.length > 0) {
    console.log(`Possible stale one-offs (${staleCandidates.length}) — consider removing:`);
    for (const r of staleCandidates.slice(0, 5)) {
        console.log(`  - ${r.slice(0, 80)}...`);
    }
    console.log();
}

if (consolidation.length > 0) {
    console.log("Consolidation opportunities:");
    for (const s of consolidation) console.log(s);
    console.log();
}

// Generate reviewed file template if it does not exist
if (!reviewedData) {
    const template = {
        reviewed: [],
        last_audit: new Date().toISOString().slice(0, 10),
        _comment: "Track reviewed permissions. Add entries as you review them."
    };
    fs.writeFileSync(REVIEWED_FILE, JSON.stringify(template, null, 2) + "\n");
}

if (unreviewed.length > 0) {
    console.log("ACTION REQUIRED: Run the interactive permissions review before proceeding.");
    console.log("See .claude/rules/permissions-review.md for the review protocol.");
}
'

exit 0
