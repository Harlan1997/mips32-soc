#!/usr/bin/env python3
"""Check the RTL D-fault owner capture/commit trace."""

import argparse
import re
import sys

CAPTURE = re.compile(
    r"^D_FAULT_OWNER_CAPTURE\s+cycle=(?P<cycle>\d+)\s+"
    r"pc=(?P<pc>[0-9a-fA-F]{8})\s+inst=(?P<inst>[0-9a-fA-F]{8})\s+"
    r"va=(?P<va>[0-9a-fA-F]{8})\s+code=(?P<code>\d+)$"
)
COMMIT = re.compile(
    r"^D_FAULT_OWNER_COMMIT\s+cycle=(?P<cycle>\d+)\s+"
    r"pc=(?P<pc>[0-9a-fA-F]{8})\s+inst=(?P<inst>[0-9a-fA-F]{8})\s+"
    r"va=(?P<va>[0-9a-fA-F]{8})\s+code=(?P<code>\d+)\s+"
    r"cp0_bad=(?P<bad>[0-9a-fA-F]{8})\s+match=(?P<match>[01])$"
)
SQUASH = re.compile(r"^D_FAULT_OWNER_SQUASH\s+")


def check(path):
    captures = []
    commits = []
    squashes = 0
    with open(path, "r", encoding="utf-8", errors="replace") as stream:
        for line_no, raw in enumerate(stream, 1):
            line = raw.strip()
            if line.startswith("D_FAULT_OWNER_CAPTURE"):
                match = CAPTURE.fullmatch(line)
                if not match:
                    raise ValueError(f"malformed capture at {path}:{line_no}")
                captures.append(match.groupdict())
            elif line.startswith("D_FAULT_OWNER_COMMIT"):
                match = COMMIT.fullmatch(line)
                if not match:
                    raise ValueError(f"malformed commit at {path}:{line_no}")
                commits.append(match.groupdict())
            elif line.startswith("D_FAULT_OWNER_SQUASH"):
                if not SQUASH.fullmatch(line):
                    raise ValueError(f"malformed squash at {path}:{line_no}")
                squashes += 1

    if not captures:
        raise ValueError("no D-fault owner captures found")
    if not commits:
        raise ValueError("no D-fault owner commits found")
    for commit in commits:
        if commit["match"] != "1":
            raise ValueError("owner commit was not marked as a match")
        if commit["va"].lower() != commit["bad"].lower():
            raise ValueError(
                f"CP0 BadVAddr mismatch: owner VA {commit['va']} vs CP0 {commit['bad']}"
            )
    print(
        f"BADVADDR_OWNER_TRACE_PASS captures={len(captures)} "
        f"commits={len(commits)} squashes={squashes}"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log")
    args = parser.parse_args()
    try:
        check(args.log)
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
