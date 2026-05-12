"""
github_client.py â€” Reusable GitHub REST API client.

Credentials are loaded from .claude/settings.local.json:
  {
    "env": {
      "GITHUB_TOKEN": "YOUR_GITHUB_TOKEN",
      "GITHUB_REPO":  "raghuvirodhula/salesforce-rca"
    }
  }

Usage:
    from scripts.github_client import GitHubClient
    gh = GitHubClient()
    pr = gh.create_pr(
        title="feat: my feature",
        body="Description of changes",
        head="feature-branch",
        base="main"
    )
    print(pr["html_url"])
"""

import json
import urllib.request
import urllib.error
import urllib.parse
from pathlib import Path


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _load_config() -> dict:
    """Load credentials from .claude/settings.local.json."""
    for candidate in [
        Path(".claude/settings.local.json"),
        Path(__file__).parent.parent / ".claude" / "settings.local.json",
    ]:
        if candidate.exists():
            return json.loads(candidate.read_text(encoding="utf-8"))
    raise FileNotFoundError("Could not find .claude/settings.local.json")


# ---------------------------------------------------------------------------
# Client
# ---------------------------------------------------------------------------

class GitHubClient:
    """Minimal GitHub REST API client using only the standard library."""

    API_BASE = "https://api.github.com"

    def __init__(self, repo: str = None):
        """
        Args:
            repo: Optional override for 'owner/repo'. Defaults to GITHUB_REPO in config.
        """
        config = _load_config()
        env = config.get("env", {})
        token = env["GITHUB_TOKEN"]
        self.repo = repo or env["GITHUB_REPO"]
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
        }

    # ------------------------------------------------------------------
    # Low-level request
    # ------------------------------------------------------------------

    def _request(self, method: str, path: str, body: dict = None) -> dict | list:
        url = f"{self.API_BASE}{path}"
        data = json.dumps(body).encode("utf-8") if body is not None else None
        req = urllib.request.Request(url, data=data, headers=self.headers, method=method)
        try:
            with urllib.request.urlopen(req) as resp:
                raw = resp.read().decode("utf-8")
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            error_body = e.read().decode("utf-8")
            raise RuntimeError(
                f"GitHub API {method} {url} failed [{e.code}]: {error_body}"
            ) from e

    def _repo(self, path: str = "") -> str:
        """Build a /repos/owner/repo/... path."""
        return f"/repos/{self.repo}{path}"

    # ------------------------------------------------------------------
    # User / repo info
    # ------------------------------------------------------------------

    def whoami(self) -> dict:
        """Return the authenticated user's profile."""
        return self._request("GET", "/user")

    def get_repo(self) -> dict:
        """Return repo metadata (stars, default branch, visibility, etc.)."""
        return self._request("GET", self._repo())

    # ------------------------------------------------------------------
    # Branches & commits
    # ------------------------------------------------------------------

    def list_branches(self) -> list:
        """List all branches."""
        return self._request("GET", self._repo("/branches"))

    def get_commit(self, ref: str = "HEAD") -> dict:
        """Get a single commit by SHA or ref."""
        return self._request("GET", self._repo(f"/commits/{ref}"))

    def list_commits(self, branch: str = None, max_results: int = 10) -> list:
        """List recent commits on a branch (defaults to repo default branch)."""
        params = urllib.parse.urlencode({"per_page": max_results, **({"sha": branch} if branch else {})})
        return self._request("GET", self._repo(f"/commits?{params}"))

    # ------------------------------------------------------------------
    # Pull Requests
    # ------------------------------------------------------------------

    def list_prs(self, state: str = "open") -> list:
        """List pull requests. state: 'open', 'closed', or 'all'."""
        params = urllib.parse.urlencode({"state": state, "per_page": 25})
        return self._request("GET", self._repo(f"/pulls?{params}"))

    def get_pr(self, pr_number: int) -> dict:
        """Fetch a pull request by number."""
        return self._request("GET", self._repo(f"/pulls/{pr_number}"))

    def create_pr(
        self,
        title: str,
        body: str,
        head: str,
        base: str = "main",
        draft: bool = False,
    ) -> dict:
        """
        Create a pull request.

        Args:
            title: PR title.
            body:  PR description (Markdown supported).
            head:  Source branch name.
            base:  Target branch (default: 'main').
            draft: Create as draft PR.

        Returns:
            PR dict including 'html_url', 'number'.
        """
        return self._request("POST", self._repo("/pulls"), {
            "title": title,
            "body": body,
            "head": head,
            "base": base,
            "draft": draft,
        })

    def merge_pr(self, pr_number: int, commit_message: str = "", method: str = "squash") -> dict:
        """
        Merge a pull request.

        Args:
            pr_number:      PR number.
            commit_message: Optional merge commit message.
            method:         'merge', 'squash', or 'rebase'.
        """
        return self._request("PUT", self._repo(f"/pulls/{pr_number}/merge"), {
            "commit_message": commit_message,
            "merge_method": method,
        })

    # ------------------------------------------------------------------
    # Issues
    # ------------------------------------------------------------------

    def list_issues(self, state: str = "open") -> list:
        """List GitHub issues (excludes PRs)."""
        params = urllib.parse.urlencode({"state": state, "per_page": 25})
        issues = self._request("GET", self._repo(f"/issues?{params}"))
        # GitHub issues endpoint includes PRs â€” filter them out
        return [i for i in issues if "pull_request" not in i]

    def create_issue(self, title: str, body: str = "", labels: list = None) -> dict:
        """Create a GitHub issue."""
        payload = {"title": title, "body": body}
        if labels:
            payload["labels"] = labels
        return self._request("POST", self._repo("/issues"), payload)

    def add_issue_comment(self, issue_number: int, comment: str) -> dict:
        """Add a comment to an issue or PR."""
        return self._request("POST", self._repo(f"/issues/{issue_number}/comments"), {"body": comment})

    # ------------------------------------------------------------------
    # Workflows / Actions
    # ------------------------------------------------------------------

    def list_workflows(self) -> list:
        """List all GitHub Actions workflows."""
        result = self._request("GET", self._repo("/actions/workflows"))
        return result.get("workflows", [])

    def list_workflow_runs(self, workflow_id: str = None, branch: str = None, max_results: int = 5) -> list:
        """List recent workflow runs."""
        params = {"per_page": max_results}
        if branch:
            params["branch"] = branch
        path = f"/actions/runs?{urllib.parse.urlencode(params)}"
        if workflow_id:
            path = f"/actions/workflows/{workflow_id}/runs?{urllib.parse.urlencode(params)}"
        result = self._request("GET", self._repo(path))
        return result.get("workflow_runs", [])

    def trigger_workflow(self, workflow_id: str, branch: str = "main", inputs: dict = None) -> None:
        """Manually trigger a workflow_dispatch workflow."""
        self._request("POST", self._repo(f"/actions/workflows/{workflow_id}/dispatches"), {
            "ref": branch,
            "inputs": inputs or {},
        })

    # ------------------------------------------------------------------
    # Contents (read files from GitHub)
    # ------------------------------------------------------------------

    def get_file(self, file_path: str, branch: str = None) -> dict:
        """
        Read a file from the repo.
        Returns dict with 'content' (base64), 'sha', 'download_url'.
        """
        params = f"?ref={branch}" if branch else ""
        return self._request("GET", self._repo(f"/contents/{file_path}{params}"))

    def get_file_content(self, file_path: str, branch: str = None) -> str:
        """Read a file and return its decoded text content."""
        import base64
        result = self.get_file(file_path, branch)
        return base64.b64decode(result["content"]).decode("utf-8")
