#!/usr/bin/env python3
"""Check the ISA boundary document for complete, non-ambiguous rows."""
from pathlib import Path
import re
import sys

path = Path(__file__).resolve().parents[1] / "docs" / "isa_implementation_matrix.md"
text = path.read_text(encoding="utf-8")
rows = [line for line in text.splitlines() if line.startswith("|") and not line.startswith("|---")]
data = [line for line in rows if "Cluster" not in line]
errors = []
for number, row in enumerate(data, 1):
    fields = [field.strip() for field in row.strip("|").split("|")]
    if len(fields) != 3 or not all(fields):
        errors.append(f"row {number}: expected three non-empty columns")
    elif fields[1] not in {"implemented", "partial", "deferred", "partial, opt-in"}:
        errors.append(f"row {number}: invalid status {fields[1]!r}")
normalized = text.lower()
for marker_group in (("full isa", "full-isa"), ("double precision",), ("branch-likely",)):
    if not any(marker in normalized for marker in marker_group):
        marker = marker_group[0]
        errors.append(f"missing residual marker: {marker}")
if errors:
    print("ISA_IMPLEMENTATION_AUDIT_FAIL")
    print("\n".join(errors))
    sys.exit(1)
print(f"ISA_IMPLEMENTATION_AUDIT_PASS rows={len(data)}")
