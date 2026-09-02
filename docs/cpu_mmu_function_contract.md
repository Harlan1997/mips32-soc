# CPU/MMU Functional Contract (RTL Frontend)

This document defines the minimum functional contract for the remaining CPU/MMU
work. It is deliberately vendor-neutral and applies to the current single-core
MIPS32 integration line. It does not claim a Linux-capable MMU or multi-core
silicon implementation.

## Baseline

- Default `SOC_MMU_ENABLE=0`; MMU gates explicitly enable it.
- Page size is 4 KiB (`PageMask=0`).
- ASID is 8 bits. ASID `0` is reserved for the bootstrap context.
- Wired TLB entries are owned by the boot/runtime map and may not be reclaimed.
- Dynamic TLB entries are owned by the current address-space context and may be
  invalidated/re-filled after a context switch.

## Software ownership contract

Each address space owns a page-table root, an ASID lease, and a generation
counter. A page-table operation is successful only when the mapping is aligned,
the physical page is in the permitted memory window, and the requested
permissions are valid. `unmap` increments the generation before releasing the
ASID; stale TLB entries must not be reused by a new lease.

The first frontend gate will use a deterministic fixed pool (four roots and
four ASIDs) so allocation failure, reuse, and isolation are observable without
requiring a heap or an operating system.

`rtl/cpu/mmu_asid_allocator.v` is the reference lease model. It reserves ASID
0, rejects stale release generations, reports pool exhaustion, and increments
the generation on a successful release before reuse.

## Shootdown contract

The current hardware is single-core. Shootdown is therefore modeled as a
logical target/mailbox transaction:

1. The owner publishes `{asid, vpn, generation, scope}` and raises a request.
2. The target acknowledges after invalidating matching dynamic entries.
3. The owner retires the request only after the acknowledgement or a bounded
   timeout.
4. A timeout is a software-visible failure; it must never silently reuse an
   ASID lease.

`scope=page` invalidates one VPN; `scope=asid` invalidates all non-wired
entries for the ASID; `scope=all` is reserved for bootstrap recovery.

The RTL reference implementation is `rtl/cpu/mmu_tlb_shootdown_mailbox.v`.
It emits a one-cycle `invalidate_valid`, rejects overlapping requests, and
reports completion or bounded timeout. It is a logical single-core endpoint;
it does not claim a physical inter-core interrupt fabric.

The APB context block now exposes the bounded page-table root lease alongside
the ASID lease.  `0x28` allocates a root and returns the root address,
`0x2c` reads its generation, `0x2c` (write) stages the release root address,
and `0x30` (write with bit 31 set) releases it using `pwdata[7:0]` as the
generation token.  Root lease events are sticky at `0x34` and are cleared by
write-one-to-clear at `0x38`.  The root allocator rejects stale generations
and increments the generation before a root can be reused.  This is a
hardware-visible bounded ownership contract; it does not provide a general
kernel allocator or Linux VM policy.

## Acceptance evidence

The CPU/MMU closure requires reproducible firmware/SoC gates for:

- allocate/map/switch/unmap/refill with four address spaces;
- ASID generation mismatch rejection and dynamic-entry isolation;
- page- and ASID-scoped shootdown, acknowledgement, and timeout;
- deterministic multi-process pressure with TLBL/TLBS/Mod recovery.

ECC injection, external EIC/VEIC routing, a real multi-core IPI fabric, and a
production kernel remain deferred dependencies.
