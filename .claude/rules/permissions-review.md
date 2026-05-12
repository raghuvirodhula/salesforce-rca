> **AI-Generated Content Disclaimer:** This document was created with the assistance of AI (Claude Code). AI can make mistakes, hallucinate commands, or reference outdated information. Verify all instructions against official documentation before use, especially in production environments. When in doubt, consult the [AWS Bedrock docs](https://docs.aws.amazon.com/bedrock/), the [Claude Code docs](https://code.claude.com/docs), and your AWS administrator.

# Interactive Permissions Review Protocol

When the session-start audit hook outputs **"ACTION REQUIRED: Run the interactive permissions review before proceeding."**, you MUST run this protocol before doing any other work. Do not skip it, summarize it away, or defer it.

## Protocol

### 1. Read current state

Read both files:
- `.claude/settings.local.json` — the active permissions
- `.claude/permissions-reviewed.json` — what has been reviewed

### 2. Identify unreviewed permissions

A permission is "unreviewed" if it does not appear in `permissions-reviewed.json` and no wildcard pattern (`:*` suffix) covers it. The audit hook output lists them — use that list.

### 3. Batch interview

Present unreviewed permissions to the user in batches using `AskUserQuestion` with `multiSelect: true`. Group by category (Bash commands, WebFetch domains, MCP tools, etc.).

For each batch:
- **Question:** "Which of these permissions should be KEPT? (Unselected items will be removed.)"
- **Options:** Each unreviewed permission as a selectable option, with a description noting any risk flags (modifies external state, looks like a one-off, etc.)
- Maximum 4 options per question (AskUserQuestion limit), so split large categories across multiple questions.

If the user selects "Other" and provides custom text, treat it as instructions (e.g., "keep all of these", "remove the docker ones").

### 4. Apply decisions

After each batch:

**For KEPT permissions:**
- Add them to `permissions-reviewed.json` in the `reviewed` array with appropriate `pattern`, `category`, and `note` fields.

**For REMOVED permissions:**
- Remove them from `settings.local.json` `permissions.allow` array.
- Add them to `permissions-reviewed.json` in the `removed` array with `pattern`, `date` (YYYY-MM-DD), and `reason` fields.

### 5. Verify

After all batches are complete, confirm:
- Re-read `.claude/settings.local.json` and `.claude/permissions-reviewed.json`
- Every entry in `settings.local.json` has a matching reviewed entry (exact or wildcard)
- Report the final count: "X permissions reviewed, Y removed, Z remaining."

## Notes

- Never add permissions to `settings.local.json` — only remove. The user adds permissions by approving Claude Code prompts during normal usage.
- The `permissions-reviewed.json` file uses `:*` suffix for wildcard prefix matching (e.g., `WebFetch:*` covers all `WebFetch(domain:...)` entries).
- `settings.local.json` is gitignored. `permissions-reviewed.json` is committed so it persists across clones.
- If there are 0 unreviewed permissions, the audit hook stays silent and this protocol does not activate.
