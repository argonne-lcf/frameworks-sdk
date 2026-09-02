#!/usr/bin/env python3
"""Convert frameworks-sdk-tests `summary.json` file(s) into a JUnit XML report.

The `frameworks-sdk-tests/smoke` CI test clones the frameworks-sdk-tests
validation suite and runs it inside a PBS job, passing `--results-dir` so
its runner writes a machine-readable `summary.json` (see `runner.py` in
argonne-lcf/frameworks-sdk-tests) into `results/` in the job workspace.
This script converts it into a JUnit XML file that GitLab CI can ingest
via `artifacts:reports:junit`, exposing the individual validation test
results in the pipeline test report.

Depends only on the Python standard library.
"""

import argparse
import glob
import json
import socket
import sys
import xml.etree.ElementTree as ET
from typing import Any, List, Mapping, Optional, Sequence

SUITE_NAME = "frameworks-sdk-tests"
DEFAULT_OUTPUT = SUITE_NAME + ".xml"
DEFAULT_GLOB = "results/*/summary.json"


def _text(value: Any) -> str:
    if value is None:
        return ""
    return str(value)


def _duration(value: Any) -> str:
    try:
        return "{:.3f}".format(float(value))
    except (TypeError, ValueError):
        return "0"


def make_testcase(result: Mapping[str, Any]) -> ET.Element:
    """Build a JUnit `<testcase>` from a summary test result."""
    case = ET.Element(
        "testcase",
        {
            "classname": _text(result.get("suite") or SUITE_NAME),
            "name": _text(result.get("id") or "unknown"),
            "time": _duration(result.get("duration_seconds")),
        },
    )
    status = _text(result.get("status"))
    reason = _text(result.get("reason"))
    if status == "fail":
        element = ET.SubElement(
            case, "failure", {"type": "failure", "message": reason}
        )
        element.text = reason
    elif status == "timeout":
        element = ET.SubElement(case, "error", {"type": "timeout", "message": reason})
        element.text = reason
    elif status == "skip":
        element = ET.SubElement(case, "skipped")
        element.text = reason
    # "pass" needs no child element.
    return case


def make_testsuite(summary: Mapping[str, Any]) -> ET.Element:
    """Build a JUnit `<testsuite>` from one `summary.json` document."""
    results: List[Mapping[str, Any]] = list(summary.get("tests") or [])
    failures = sum(1 for result in results if result.get("status") == "fail")
    errors = sum(1 for result in results if result.get("status") == "timeout")
    skipped = sum(1 for result in results if result.get("status") == "skip")
    harness_error = summary.get("harness_error")
    if summary.get("interrupted") and not harness_error:
        harness_error = "interrupted before completing"
    if harness_error:
        errors += 1
    suite = ET.Element(
        "testsuite",
        {
            "name": SUITE_NAME,
            "tests": str(len(results) + (1 if harness_error else 0)),
            "failures": str(failures),
            "errors": str(errors),
            "skipped": str(skipped),
            "time": _duration(summary.get("duration_seconds")),
            "timestamp": _text(summary.get("started_at")),
            "hostname": socket.gethostname(),
        },
    )
    if harness_error:
        case = ET.Element(
            "testcase", {"classname": SUITE_NAME, "name": "harness", "time": "0"}
        )
        element = ET.SubElement(
            case, "error", {"type": "harness", "message": _text(harness_error)}
        )
        element.text = _text(harness_error)
        suite.append(case)
    for result in results:
        suite.append(make_testcase(result))
    return suite


def indent(element: ET.Element, level: int = 0) -> None:
    """Pretty-print helper for `xml.etree` (like `ET.indent` on Python 3.9+)."""
    padding = "\n" + "  " * level
    child: Optional[ET.Element] = None
    if len(element):
        if not (element.text or "").strip():
            element.text = padding + "  "
        for child in element:
            indent(child, level + 1)
        if not (child.tail or "").strip():
            child.tail = padding
    if level and not (element.tail or "").strip():
        element.tail = padding


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Convert frameworks-sdk-tests summary.json to JUnit XML."
    )
    parser.add_argument(
        "summaries",
        nargs="*",
        help="summary.json file(s) (default: {} in the current directory)".format(
            DEFAULT_GLOB
        ),
    )
    parser.add_argument(
        "-o",
        "--output",
        default=DEFAULT_OUTPUT,
        help="output JUnit XML file (default: {})".format(DEFAULT_OUTPUT),
    )
    args = parser.parse_args(argv)

    paths = args.summaries or sorted(glob.glob(DEFAULT_GLOB))
    if not paths:
        print(
            "{}: no {} found; nothing to convert".format(
                parser.prog, DEFAULT_GLOB
            ),
            file=sys.stderr,
        )
        return 0

    root = ET.Element("testsuites")
    for path in paths:
        try:
            with open(path, encoding="utf-8") as handle:
                summary = json.load(handle)
            if not isinstance(summary, dict) or not isinstance(
                summary.get("tests"), list
            ):
                raise ValueError("not a frameworks-sdk-tests summary")
        except (OSError, ValueError) as error:
            print(
                "{}: skipping {}: {}".format(parser.prog, path, error),
                file=sys.stderr,
            )
            continue
        root.append(make_testsuite(summary))

    if len(root) == 0:
        print(
            "{}: no valid summary files; nothing to convert".format(
                parser.prog
            ),
            file=sys.stderr,
        )
        return 0

    indent(root)
    ET.ElementTree(root).write(args.output, encoding="utf-8", xml_declaration=True)
    print("{}: wrote {}".format(parser.prog, args.output))
    return 0


if __name__ == "__main__":
    sys.exit(main())
