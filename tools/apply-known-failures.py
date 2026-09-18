#!/usr/bin/env python3
"""Patch a frameworks-sdk-tests manifest with known-failure skip entries.

The frameworks-sdk CI pipeline runs the frameworks-sdk-tests validation
suite and stays green only if every selected test passes. Tests with
known, unfixed issues are tracked in a JSON file (mapping test id to a
skip reason) inside this repository; this script disables each of
those tests in a cloned `suite.json` manifest, recording the reason in
`skip_reason`, so the runner reports them as skipped instead of failed.
Remove an entry from the known-failures file once the underlying issue
is fixed to re-enable the test.

Depends only on the Python standard library.
"""

import argparse
import json
import pathlib
import sys
from collections.abc import Mapping
from typing import Any


def _load_json(path: pathlib.Path, kind: str) -> Any:
    """Parse a JSON document, or print an error and return None."""
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError) as error:
        print(
            f"{path}: cannot read {kind} file: {error}",
            file=sys.stderr,
        )
        return None


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Disable known-failing tests in a suite.json manifest."
    )
    parser.add_argument(
        "--manifest",
        default="suite.json",
        help="frameworks-sdk-tests manifest to patch in place (default: suite.json)",
    )
    parser.add_argument(
        "--known-failures",
        required=True,
        help="JSON file mapping test ids to skip reasons",
    )
    args = parser.parse_args()

    manifest_path = pathlib.Path(args.manifest)
    failures_path = pathlib.Path(args.known_failures)

    manifest = _load_json(manifest_path, "manifest")
    failures = _load_json(failures_path, "known-failures")
    if manifest is None or failures is None:
        return 2
    if not isinstance(manifest, Mapping) or not isinstance(manifest.get("tests"), list):
        print(
            f"{manifest_path}: not a frameworks-sdk-tests manifest",
            file=sys.stderr,
        )
        return 2
    if not isinstance(failures, Mapping):
        print(
            f"{failures_path}: not a JSON object mapping ids to reasons",
            file=sys.stderr,
        )
        return 2

    tests: list[dict[str, Any]] = manifest["tests"]
    known_ids = {test.get("id") for test in tests}

    patched = 0
    for test in tests:
        reason = failures.get(test.get("id"))
        if reason is None:
            continue
        if not isinstance(reason, str) or not reason.strip():
            print(
                "{}: skip reason for {} must be a non-empty string".format(
                    failures_path, test.get("id")
                ),
                file=sys.stderr,
            )
            return 2
        test["enabled"] = False
        test["skip_reason"] = reason
        patched += 1

    missing = sorted(set(failures) - known_ids)
    if missing:
        print(
            "{}: not in {} (fixed/renamed upstream?): remove them from the list".format(
                ", ".join(missing), manifest_path
            ),
            file=sys.stderr,
        )

    try:
        with open(manifest_path, "w", encoding="utf-8") as handle:
            json.dump(manifest, handle, indent=1)
            handle.write("\n")
    except OSError as error:
        print(
            f"{manifest_path}: cannot write manifest: {error}",
            file=sys.stderr,
        )
        return 2

    print(f"{manifest_path}: disabled {patched} test(s) per {failures_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
