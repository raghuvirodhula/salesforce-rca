"""
jira_client.py — Reusable JIRA REST API v3 client.

Credentials are loaded from .claude/settings.local.json:
  {
    "env": {
      "JIRA_URL":       "https://your-instance.atlassian.net",
      "JIRA_USERNAME":  "your-email@example.com",
      "JIRA_API_TOKEN": "YOUR_API_TOKEN"
    }
  }

Usage:
    from scripts.jira_client import JiraClient
    jira = JiraClient()
    issue = jira.create_issue(
        project_key="KAN",
        summary="My story",
        description="Some description text",
        issue_type="Story",
        labels=["label1"]
    )
    print(issue["key"])
"""

import json
import base64
import urllib.request
import urllib.error
from pathlib import Path


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _load_config() -> dict:
    """Load credentials from .claude/settings.local.json (project root)."""
    for candidate in [
        Path(".claude/settings.local.json"),
        Path(__file__).parent.parent / ".claude" / "settings.local.json",
    ]:
        if candidate.exists():
            return json.loads(candidate.read_text(encoding="utf-8"))
    raise FileNotFoundError(
        "Could not find .claude/settings.local.json. "
        "Ensure JIRA_URL, JIRA_USERNAME and JIRA_API_TOKEN are set in it."
    )


def text_to_adf(text: str) -> dict:
    """
    Convert a plain-text string to Atlassian Document Format (ADF).
    JIRA REST API v3 requires descriptions in this format.
    Each non-empty line becomes its own paragraph.
    """
    paragraphs = []
    for line in text.split("\n"):
        line = line.strip()
        if line:
            paragraphs.append({
                "type": "paragraph",
                "content": [{"type": "text", "text": line}]
            })
    if not paragraphs:
        paragraphs = [{"type": "paragraph", "content": [{"type": "text", "text": " "}]}]
    return {"version": 1, "type": "doc", "content": paragraphs}


# ---------------------------------------------------------------------------
# Client
# ---------------------------------------------------------------------------

class JiraClient:
    """Minimal JIRA REST API v3 client using only the standard library."""

    def __init__(self):
        config = _load_config()
        env = config.get("env", {})
        self.base_url = env["JIRA_URL"].rstrip("/")
        username = env["JIRA_USERNAME"]
        token = env["JIRA_API_TOKEN"]
        creds = base64.b64encode(f"{username}:{token}".encode("ascii")).decode("ascii")
        self.headers = {
            "Authorization": f"Basic {creds}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

    # ------------------------------------------------------------------
    # Low-level request
    # ------------------------------------------------------------------

    def _request(self, method: str, path: str, body: dict = None) -> dict:
        url = f"{self.base_url}/rest/api/3/{path.lstrip('/')}"
        data = json.dumps(body).encode("utf-8") if body is not None else None
        req = urllib.request.Request(url, data=data, headers=self.headers, method=method)
        try:
            with urllib.request.urlopen(req) as resp:
                raw = resp.read().decode("utf-8")
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            error_body = e.read().decode("utf-8")
            raise RuntimeError(
                f"JIRA API {method} {url} failed [{e.code}]: {error_body}"
            ) from e

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def whoami(self) -> dict:
        """Return the authenticated user's profile — useful as a connection test."""
        return self._request("GET", "myself")

    def get_projects(self) -> list:
        """Return all accessible projects."""
        return self._request("GET", "project")

    def get_issue(self, issue_key: str) -> dict:
        """Fetch a single issue by key (e.g. 'KAN-1')."""
        return self._request("GET", f"issue/{issue_key}")

    def search_issues(self, jql: str, max_results: int = 50) -> list:
        """
        Run a JQL query and return a list of issues.
        Uses the current JIRA Cloud endpoint: POST /rest/api/3/search/jql
        """
        body = {
            "jql": jql,
            "maxResults": max_results,
            "fields": ["summary", "status", "assignee", "issuetype", "priority"]
        }
        result = self._request("POST", "search/jql", body)
        return result.get("issues", [])

    def create_issue(
        self,
        project_key: str,
        summary: str,
        description: str = "",
        issue_type: str = "Story",
        labels: list = None,
        priority: str = None,
    ) -> dict:
        """
        Create a JIRA issue.

        Args:
            project_key: Project key, e.g. 'KAN'.
            summary:     Issue title.
            description: Plain-text description (auto-converted to ADF).
            issue_type:  e.g. 'Story', 'Bug', 'Task'.
            labels:      Optional list of label strings.
            priority:    Optional priority name, e.g. 'High'.

        Returns:
            Dict with at minimum {'id': ..., 'key': ..., 'self': ...}.
        """
        fields: dict = {
            "project": {"key": project_key},
            "summary": summary,
            "description": text_to_adf(description),
            "issuetype": {"name": issue_type},
        }
        if labels:
            fields["labels"] = labels
        if priority:
            fields["priority"] = {"name": priority}

        return self._request("POST", "issue", {"fields": fields})

    def update_issue(self, issue_key: str, fields: dict) -> None:
        """
        Update fields on an existing issue.

        Args:
            issue_key: e.g. 'KAN-1'.
            fields:    Dict of field updates (plain strings are NOT auto-converted to ADF).
        """
        self._request("PUT", f"issue/{issue_key}", {"fields": fields})

    def add_comment(self, issue_key: str, comment: str) -> dict:
        """Add a plain-text comment to an issue (auto-converted to ADF)."""
        body = {"body": text_to_adf(comment)}
        return self._request("POST", f"issue/{issue_key}/comment", body)

    def transition_issue(self, issue_key: str, transition_name: str) -> None:
        """
        Move an issue to a new status by transition name (e.g. 'In Progress').
        Fetches available transitions first to match by name.
        """
        transitions = self._request("GET", f"issue/{issue_key}/transitions").get("transitions", [])
        match = next((t for t in transitions if t["name"].lower() == transition_name.lower()), None)
        if not match:
            available = [t["name"] for t in transitions]
            raise ValueError(f"Transition '{transition_name}' not found. Available: {available}")
        self._request("POST", f"issue/{issue_key}/transitions", {"transition": {"id": match["id"]}})
