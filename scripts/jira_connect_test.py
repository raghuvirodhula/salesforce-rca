"""
jira_connect_test.py — Verify JIRA connection and list open issues.

Run from the project root:
    python scripts/jira_connect_test.py
"""

import sys
from pathlib import Path

# Allow running from project root without installing the package
sys.path.insert(0, str(Path(__file__).parent.parent))

from scripts.jira_client import JiraClient

def main():
    print("Connecting to JIRA...")
    jira = JiraClient()

    # 1. Who am I?
    me = jira.whoami()
    print(f"\n[OK] Connected as: {me.get('displayName')} ({me.get('emailAddress')})")

    # 2. List projects
    projects = jira.get_projects()
    print(f"\n[PROJECTS] Accessible projects ({len(projects)}):")    
    for p in projects:
        print(f"   [{p['key']}] {p['name']}")

    # 3. Open issues in KAN project
    print("\n[ISSUES] Open issues in KAN project:")
    issues = jira.search_issues("project = KAN ORDER BY created DESC", max_results=10)
    if issues:
        for issue in issues:
            status = issue["fields"]["status"]["name"]
            summary = issue["fields"]["summary"]
            print(f"   {issue['key']} [{status}] {summary}")
    else:
        print("   No open issues found.")

if __name__ == "__main__":
    main()
