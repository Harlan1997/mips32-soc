# Formal Verification Harness (Phase F)

Property scaffolds for JasperGold / VC Formal and a solver-independent content
audit. The current environment has no formal engine, so the audit and
simulation assertions are not formal proof results.

## Scope (per `docs/vplan.md`)

Formal-proven modules and property categories:

| Module | Property class | Proof type |
|---|---|---|
| `axi_arbiter_2x1_full` | fairness, single-outstanding, deadlock freedom | assume-guarantee |
| `dcache` | coherence FSM invariants, no data loss on refill | bounded |
| `l2_cache` (future) | MSHR count invariants, deadlock | bounded |
| `mips_tlb` | one-hot state, TLB entry read-after-write consistency | full proof |
| `mips_cp0` | exception priority ordering, no exception loss | bounded |
| `apb_pic` | priority encoder correctness, no lost IRQ | full proof |

## Directory layout (planned)

```
tb/formal/
  README.md                          ← this file
  common/
    assume_reset.sva                 ← common reset assumptions
    assume_axi_master_wellformed.sva ← well-formed AXI master assumes
  arbiter/
    arb_props.sva
    arb_jgproj.tcl                   ← JasperGold project script
  tlb/
    tlb_props.sva
    tlb_jgproj.tcl
  ...
```

## Current property assets

- `arb_fairness.sva`: bounded arbiter fairness.
- `dcache_invariants.sva`: known-state and bounded refill completion.
- `tlb_invariants.sva`: lookup multi-hit consistency.
- `interrupt_priority.sva`: selected-source safety checks.
- `formal_bind.sv`: real `dcache`, `mips_tlb` and `apb_vic` bindings under
  `FORMAL_ENABLE`.

## Wiring in (future work)

1. License: JasperGold / VC Formal (target ~2 seat lease)
2. Regress: nightly bounded proofs on modified modules only
3. Waivers: `docs/formal_waivers.md` for bounded-only properties

## Placeholder property (arbiter fairness)

See `arb_fairness.sva` — expresses that within any
1000-cycle window, if M0 has continuously asserted arvalid while M1 has
been idle, M0 must have received at least one arready. Real proof will
require refining assumptions on downstream slave arready behavior.
