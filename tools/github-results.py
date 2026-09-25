#!/usr/bin/env python3
"""Publish frameworks-sdk-tests results to GitHub.

Dispatches the `test-report` workflow with the JUnit XML reports and the
per-test summary from the runner's `results/*/summary.json` files. The
workflow renders the summary as a check run on the pipeline's commit and
publishes the reports as workflow artifacts.

The reports are gzipped because the dispatch payload is capped at 64 KB and
`report.xml` embeds the job logs; the workflow decompresses them verbatim.

Nothing is sent when GITHUB_TOKEN or CI_COMMIT_SHA is unset, so the job
keeps working until the CI variables are configured.

Depends only on the Python standard library.
"""

import base64
import gzip
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

API = "https://api.github.com"
REPOSITORY = os.environ.get("GITHUB_REPOSITORY", "argonne-lcf/frameworks-sdk")
REPORTS = ("frameworks-sdk-tests.xml", "report.xml")
STATUSES = ("pass", "fail", "skip")


def api(path, token, payload):
    """POST to the GitHub API; refuse anything but https://api.github.com."""
    url = API + path
    if not url.startswith(API + "/"):
        raise RuntimeError(f"refusing to call {url}")
    request = urllib.request.Request(  # noqa: S310
        url,
        data=json.dumps(payload).encode(),
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:  # noqa: S310
            return json.loads(response.read() or b"{}")
    except (urllib.error.URLError, ValueError) as error:
        raise RuntimeError(f"POST {path} failed: {error}") from error


def read_results():
    """Return (tests, totals) from the runner's summary.json files."""
    try:
        summaries = [
            json.loads(path.read_text(encoding="utf-8"))
            for path in sorted(pathlib.Path("results").glob("*/summary.json"))
        ]
    except (OSError, ValueError) as error:
        raise RuntimeError(f"cannot read results: {error}") from error
    tests = [
        {
            "id": case.get("id") or "unknown",
            "status": case.get("status") if case.get("status") in STATUSES else "fail",
            "reason": (case.get("reason") or "").strip(),
        }
        for summary in summaries
        for case in summary.get("tests") or []
    ]
    totals = {
        status: sum(1 for test in tests if test["status"] == status)
        for status in STATUSES
    }
    return tests, totals


def read_reports():
    """Return the JUnit XML reports, gzipped and base64-encoded."""
    return {
        name: base64.b64encode(gzip.compress(pathlib.Path(name).read_bytes())).decode()
        for name in REPORTS
        if pathlib.Path(name).is_file()
    }


def main():
    token = os.environ.get("GITHUB_TOKEN", "")
    sha = os.environ.get("CI_COMMIT_SHA", "")
    pipeline = os.environ.get("CI_PIPELINE_URL", "")
    if not token or not sha:
        print("github-results: GITHUB_TOKEN/CI_COMMIT_SHA unset; nothing published")
        return 0

    try:
        tests, totals = read_results()
        reports = read_reports()
    except (RuntimeError, OSError) as error:
        print(f"github-results: {error}", file=sys.stderr)
        return 1
    if not tests:
        print("github-results: no results to publish", file=sys.stderr)
        return 1

    print(
        f"github-results: {totals['pass']} passed, {totals['skip']} skipped, "
        f"{totals['fail']} failed"
    )
    try:
        api(
            f"/repos/{REPOSITORY}/dispatches",
            token,
            {
                "event_type": "test-report",
                "client_payload": {
                    "sha": sha,
                    "pipeline": pipeline,
                    "totals": totals,
                    "tests": tests,
                    "reports": reports,
                },
            },
        )
    except RuntimeError as error:
        print(f"github-results: {error}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
