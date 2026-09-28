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
- `docs/rtl_linux_differential_fix_plan.md`
- `docs/rtl_linux_differential_fix_plan_v2.md`
- `docs/rtl_linux_differential_fix_plan_v3.md` (diagnostic baseline)
- `docs/rtl_linux_differential_fix_plan_v4.md` (previous execution plan)
- `docs/rtl_linux_differential_fix_plan_v5.md` (previous execution plan)
- `docs/rtl_linux_differential_fix_plan_v6.md` (previous execution plan)
- `docs/rtl_linux_differential_fix_plan_v7.md` (previous execution plan: target load/memory-owner closure)
- `docs/rtl_linux_differential_fix_plan_v8.md` (current execution plan: post-fix review and owner classification)
- `docs/rtl_linux_differential_fix_plan_v9.md` (current execution plan: DDR contents versus data-response owner classification)
- `docs/rtl_linux_differential_fix_plan_v10.md` (current execution plan: CPU store-operand owner classification and focused functional fix)
- `docs/rtl_linux_differential_fix_plan_v11.md` (current execution plan: deterministic guest entropy contract, valid differential inputs, and post-contract owner fix)
- `docs/rtl_linux_differential_fix_plan_v12.md` (current execution plan: canonical manifest, deterministic repeatability, fail-closed trace validation, and post-contract owner classification)
- `docs/rtl_linux_differential_fix_plan_v13.md` (current execution plan: RTL Linux WAIT/timer blocker classification and staged closure)
- `docs/rtl_linux_differential_fix_plan_v14.md` (current execution plan: LL/SC owner classification, generic Linux progress, and QEMU environment recovery)
- `docs/rtl_linux_differential_fix_plan_v15.md` (current execution plan: post-`devtmpfs` scheduler/task-state ownership, cache visibility, and fail-closed Linux differential)
- `docs/rtl_linux_differential_fix_plan_v16.md` (current execution plan: first post-`devtmpfs` RTL/QEMU architectural divergence and one owner-scoped fix)
- `docs/rtl_linux_differential_fix_plan_v19.md` (current execution plan: first post-`devtmpfs` architectural divergence and generic RTL Linux closure)
- `docs/rtl_linux_differential_fix_plan_v20.md` (superseded execution plan: fail-closed image identity, valid same-DTB differential, and first-mismatch ownership)
- `docs/rtl_linux_differential_fix_plan_v21.md` (superseded execution plan: initial terminal-marker QEMU/RTL Linux closure)
- `docs/rtl_linux_differential_fix_plan_v22.md` (superseded execution plan: coupled terminal-marker QEMU/RTL Linux closure)
- `docs/rtl_linux_differential_fix_plan_v23.md` (current execution plan: standalone compact QEMU terminal closure; RTL differential remains open)
- `docs/qemu_reference_model.md` (verified custom `mips32-soc-ref` QEMU model identity and closure evidence)
- `docs/rtl_linux_generic_userspace_closure_20260929.md` (current generic RTL Linux userspace terminal-marker closure)

Module contracts are under `docs/block_specs/`. Historical architecture and
session notes are under `docs/archive/` and are not signoff authority.
