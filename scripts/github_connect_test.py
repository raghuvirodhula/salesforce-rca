"""
github_connect_test.py — Verify GitHub connection and show repo status.

Run from the project root:
    python scripts/github_connect_test.py
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from scripts.github_client import GitHubClient

def main():
    print("Connecting to GitHub...")
    gh = GitHubClient()

    # 1. Who am I?
    me = gh.whoami()
    print(f"\n[OK] Authenticated as: {me['login']} ({me.get('name') or 'no name set'})")

    # 2. Repo info
    repo = gh.get_repo()
    print(f"\n[REPO] {repo['full_name']}")
    print(f"  Default branch : {repo['default_branch']}")
    print(f"  Visibility     : {'private' if repo['private'] else 'public'}")
    print(f"  Stars          : {repo['stargazers_count']}")
    print(f"  URL            : {repo['html_url']}")

    # 3. Branches
    branches = gh.list_branches()
    print(f"\n[BRANCHES] ({len(branches)} total)")
    for b in branches:
        print(f"  {b['name']}")

    # 4. Recent commits
    commits = gh.list_commits(max_results=5)
    print(f"\n[COMMITS] Last {len(commits)} commits on default branch:")
    for c in commits:
        sha = c['sha'][:7]
        msg = c['commit']['message'].split('\n')[0][:70]
        author = c['commit']['author']['name']
        print(f"  {sha}  {author}: {msg}")

    # 5. Open PRs
    prs = gh.list_prs(state="open")
    print(f"\n[PULL REQUESTS] Open: {len(prs)}")
    for pr in prs:
        print(f"  #{pr['number']} [{pr['head']['ref']} -> {pr['base']['ref']}] {pr['title']}")
    if not prs:
        print("  No open PRs")

    # 6. Workflows
    workflows = gh.list_workflows()
    print(f"\n[WORKFLOWS] ({len(workflows)} defined)")
    for w in workflows:
        print(f"  {w['name']} [{w['state']}]  {w['path']}")

    print("\n[DONE] GitHub connection successful.")

if __name__ == "__main__":
    main()
