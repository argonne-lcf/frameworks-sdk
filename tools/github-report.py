#!/usr/bin/env python3
"""Render a frameworks-sdk-tests dispatch as a check run and job summary."""

import base64
import gzip
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

API = "https://api.github.com"
CHECK_NAME = "frameworks-sdk-tests"
# Checks API limit: 50 annotations per request
ANNOTATION_BATCH = 50
# summary.json has no file or line for a test
ANNOTATION_PATH = "tests/frameworks-sdk-tests.bats"


def api(method, path, payload, token):
    request = urllib.request.Request(  # noqa: S310
        API + path,
        data=json.dumps(payload).encode(),
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:  # noqa: S310
            return json.loads(response.read() or b"{}")
    except (urllib.error.URLError, ValueError) as error:
        raise RuntimeError(f"{method} {path} failed: {error}") from error


def batch(items, size):
    return [items[start : start + size] for start in range(0, len(items), size)] or [[]]


def annotation(test):
    return {
        "path": ANNOTATION_PATH,
        "start_line": 1,
        "end_line": 1,
        "annotation_level": "failure",
        "title": test["id"],
        "message": test["reason"] or "failed",
    }


def check_output(body, annotations):
    # title and summary are required whenever output is sent
    return {"title": CHECK_NAME, "summary": body, "annotations": annotations}


def failures_in(run):
    """Failures, in either payload shape."""
    if "failures" in run:
        return list(run["failures"])
    return [t for t in run.get("tests") or [] if t.get("status") == "fail"]


def render(run):
    """Markdown body and failures."""
    totals = run["totals"]
    failed = failures_in(run)
    lines = [f"{totals['pass']} passed, {totals['skip']} skipped, {totals['fail']} failed"]
    if run.get("pipeline"):
        lines += ["", f"Pipeline: {run['pipeline']}"]
    if failed:
        lines += ["", "| test | suite | result |", "| --- | --- | --- |"]
        lines += [
            f"| `{t['id']}` | `{t.get('suite') or '-'}` | {t['reason'] or 'failed'} |"
            for t in failed
        ]
    if run.get("omitted_failures"):
        lines += ["", f"_{run['omitted_failures']} further failures not listed._"]
    reports = ", ".join(f"`{n}`" for n in sorted(run.get("reports") or {}))
    if run.get("omitted_reports"):
        reports += f" ({len(run['omitted_reports'])} omitted: too large to dispatch)"
    lines += ["", f"Reports: {reports or 'none'}"]
    return "\n".join(lines), failed


def read_payload():
    try:
        return json.loads(os.environ["PAYLOAD"])
    except KeyError as error:
        raise RuntimeError("PAYLOAD is unset") from error
    except ValueError as error:
        raise RuntimeError(f"invalid dispatch: {error}") from error


def publish(run, body, failed, repo, token):
    groups = batch([annotation(t) for t in failed], ANNOTATION_BATCH)
    check = api(
        "POST",
        f"/repos/{repo}/check-runs",
        {
            "name": CHECK_NAME,
            "head_sha": run["sha"],
            "status": "completed",
            "conclusion": "failure" if failed else "success",
            "output": check_output(body, groups[0]),
        },
        token,
    )
    for group in groups[1:]:
        api(
            "PATCH",
            f"/repos/{repo}/check-runs/{check['id']}",
            {"output": check_output(body, group)},
            token,
        )
    return check["id"]


def write_reports(run):
    for name, blob in (run.get("reports") or {}).items():
        path = pathlib.Path(name)
        path.write_bytes(gzip.decompress(base64.b64decode(blob)))
        print(f"github-report: wrote {name} ({path.stat().st_size} bytes)")


def write_summary(body):
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary:
        return
    try:
        with pathlib.Path(summary).open("a", encoding="utf-8") as out:
            out.write(body + "\n")
    except OSError as error:
        # still post the check run
        print(f"github-report: cannot write job summary: {error}", file=sys.stderr)


def main():
    try:
        run = read_payload()
    except RuntimeError as error:
        print(f"github-report: {error}", file=sys.stderr)
        return 1
    body, failed = render(run)

    token = os.environ.get("GITHUB_TOKEN", "")
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    if not token or not repo:
        print(
            "github-report: GITHUB_TOKEN/GITHUB_REPOSITORY unset; nothing published",
            file=sys.stderr,
        )
        return 1

    # written before the API calls
    write_summary(body)
    write_reports(run)
    try:
        check_id = publish(run, body, failed, repo, token)
    except RuntimeError as error:
        print(f"github-report: {error}", file=sys.stderr)
        return 1
    print(f"github-report: check run {check_id} with {len(failed)} annotations")
    return 0


if __name__ == "__main__":
    sys.exit(main())
