#!/usr/bin/env python3
"""Audit formal-property fallback assets without requiring a solver."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
FORMAL = ROOT / "tb" / "formal"
REQUIRED = {"arbiter": FORMAL / "arb_fairness.sva"}

errors = []
seen_modules = set()
assertion_count = 0
formal_files = sorted(FORMAL.glob("*.sva"))
for path in formal_files:
    source = path.read_text(encoding="utf-8")
    modules = re.findall(r"\bmodule\s+([A-Za-z_][A-Za-z0-9_$]*)\b", source)
    assertions = re.findall(r"\bassert\s+property\s*\(", source)
    seen_modules.update(modules)
    assertion_count += len(assertions)
    if not modules:
        errors.append(f"{path.relative_to(ROOT)}: no module declaration")
    if not assertions:
        errors.append(f"{path.relative_to(ROOT)}: no assert property")
    if re.search(r"\bdisable\s+iff\s*\(\s*1'b0\s*\)", source):
        errors.append(f"{path.relative_to(ROOT)}: permanently disabled assertion")

for name, path in REQUIRED.items():
    if not path.is_file() or not path.stat().st_size:
        errors.append(f"missing required {name} asset: {path.relative_to(ROOT)}")

for waiver in sorted((ROOT / "tb" / "coverage").glob("*.el")):
    source = waiver.read_text(encoding="utf-8")
    if re.search(r"(^|\s)(all[_ -]?metrics|all metrics)(\s|$)|\*.*(module|metric)", source, re.I):
        errors.append(f"broad waiver selector: {waiver.relative_to(ROOT)}")

if errors:
    print("FORMAL_ASSET_AUDIT_FAIL")
    print("\n".join(errors))
    sys.exit(1)

print(
    "FORMAL_ASSET_AUDIT_PASS "
    f"files={len(formal_files)} modules={len(seen_modules)} "
    f"assertions={assertion_count}"
)
