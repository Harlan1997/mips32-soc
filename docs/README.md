# SoC Refactor Docs

This directory contains the current RTL contract, functional evidence,
verification gates, and supporting architecture records.

Start here:
- `docs/target_architecture.md`
- `docs/address_map.md`
- `docs/functional_completeness_plan.md`
- `docs/functional_evidence_registry.md`
- `docs/repo_layout.md`
- `docs/coverage_plan.md`
- `docs/signoff_criteria.md`
- `docs/rtl_linux_differential_remediation_plan.md` (active Linux differential remediation & closure plan)
- `docs/qemu_reference_model.md` (verified custom `mips32-soc-ref` QEMU model identity and closure evidence)
- `docs/rtl_linux_generic_userspace_closure_20260929.md` (current generic RTL Linux userspace terminal-marker closure)

Module contracts are under `docs/block_specs/`. Historical architecture,
session notes, and superseded differential fix plans (`rtl_linux_differential_fix_plan*.md`)
are under `docs/archive/` and are not signoff authority.
