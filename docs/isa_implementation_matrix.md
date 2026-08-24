# MIPS32 ISA Implementation Matrix

This matrix is the executable boundary for the current CPU RTL. `implemented`
means the decoder, pipeline behavior, and at least one directed gate exist.
`partial` means an encoding or behavioral slice exists but the architectural
contract is incomplete. `deferred` is an intentional unsupported feature and
must raise Reserved Instruction (or the specified coprocessor exception).

| Cluster | Status | Current evidence / boundary |
|---|---|---|
| SPECIAL integer ALU, shifts, compares and trap instructions | implemented | `isa-r2-gate`, ALU/unit regressions, `qemu-system-trap-differential-gate`; R-type `TGE/TGEU/TLT/TLTU/TEQ/TNE` and REGIMM immediate `TGEI/TGEIU/TLTI/TLTIU/TEQI/TNEI` raise precise ExcCode 13 in the selected system retire corpus |
| SPECIAL control flow J/JAL/JR/JALR and REGIMM basic/link | implemented | CPU/CP0 and ISA R2 firmware gates; the R2 JR.HB/JALR.HB encodings and EHB barrier encoding are exercised by the ISA R2 SoC sweep |
| SPECIAL2 MDU, MUL/MADD/MSUB, CLZ/CLO | implemented | `mdu-cpu-gate`, ISA R2 sweep |
| SPECIAL3 EXT/INS, BSHFL/BITSWAP, RDHWR | partial | `make isa-r2-gate mips-control-special3-gate bitswap-gate`; EXT/INS/RDHWR, BITSWAP and all three other contract BSHFL operations have directed behavior/encoding coverage, including reserved `sa` values and fixed-`rs` checks; full ISA compliance remains deferred |
| Immediate integer ALU and LUI | implemented | CPU firmware regression |
| Integer loads/stores, merge LWL/LWR/SWL/SWR | partial | aligned and unaligned slices; cross-page/ABI policy remains |
| LL/SC | partial | single-core reservation and CPU gate; full SMP reservation policy remains |
| Branch-likely BEQL/BNEL/BLEZL/BGTZL and REGIMM-likely | implemented | `branch-likely-gate`; taken delay slot, not-taken annulment, and BLTZALL/BGEZALL link condition |
| CACHE and SYNCI | partial | `make mips-control-cache-gate` plus CPU/I-cache maintenance gates; all 10 implemented CACHE codes and 5 reserved codes are decoder-checked, with selected I/D maintenance and SYNCI behavior; full cache ordering/ABI remains |
| PREF/PREFX/SYNC/WAIT | partial | `make qemu-system-wait-differential-gate qemu-system-isa-r2-differential-gate`; PREF/PREFX/SYNC no-trap slices and WAIT interrupt wakeup/ERET are covered; PREFX is an ordered integer no-op when COP1 is disabled; full memory-ordering and physical interrupt timing remain |
| COP0 register access, exceptions, TLB ops, DI/EI/ERET | partial | `make mips-control-cp0-gate mips-control-srs-gate mips-regfile-srs-gate srs-gate qemu-system-srs-map-differential-gate srs-nested-gate` plus CP0/TLB/exception/DI-EI/WAIT gates; the SRS subset is opt-in: default `SOC_SRS_ENABLE=0` keeps RDPGPR/WRPGPR as RI, while opt-in software-selected bank access, IP-based SRSMap entry and EXL-held nested policy are CPU/SoC verified. Full privileged/Linux context semantics and external VEIC/EICSS mode remain open |
| COP1 single precision and conditional moves | partial, opt-in | `fpu-single-gate` covers single arithmetic, COP1X `MADD.S/MSUB.S/NMADD.S/NMSUB.S`, `RECIP.S/RSQRT.S`, `CVT.S.W`, `CVT.W.S`, `ROUND/TRUNC/CEIL/FLOOR.W.S`, MTC1/MFC1/CFC1, `MOVZ.S/MOVN.S`, all eight FCC selectors for compare/BC1/MOVF/MOVT, FCSR[23]/[25:31] mapping, and an immediate CFC1-to-integer consumer chain; `qemu-system-fpu-single-differential-gate` compares the same path through retire (`TRACE_COMPARE_PASS records=1248`); `mips-control-fpu-cond-gate` covers COP1X encodings, integer condition fields, reserved fields, D-pair parity and MTHI regression; CU1 exception gate remains passing |
| COP1 compare and BC1F/BC1T/BC1FL/BC1TL | partial, opt-in | `mips-fpu-compare-gate` covers all 16 C.* predicates for single- and double-precision finite ordered/equal and NaN vectors; `fpu-branch-gate qemu-system-fpu-branch-differential-gate` covers FCSR condition-bit branch behavior, ordinary delay slots, and likely annul/taken paths. Precise IEEE-754 signaling/quiet invalid policy and FPE delivery remain partial |
| COP1 single-precision LWC1/SWC1 | partial, opt-in | `fpu-single-gate`; real CPU/D-cache/DDR word path with FPR load-use hazard coverage |
| COP1 double precision | partial, opt-in | `fpu-double-gate`; even-register pair path covers ADD.D/SUB.D/MUL.D/DIV.D/ABS.D/MOV.D/NEG.D, COP1X `MADD.D/MSUB.D/NMADD.D/NMSUB.D`, `RECIP.D/RSQRT.D`, `MOVZ.D/MOVN.D`, plus the selected double/single and integer conversion path; QEMU system retire differential passes the same corpus (`TRACE_COMPARE_PASS records=225`) |
| COP1 double conversion and fixed-rounding slice | partial, opt-in | `fpu-double-gate qemu-system-fpu-double-differential-gate`; CVT.S.D/CVT.D.S/CVT.D.W/CVT.W.D and ROUND/TRUNC/CEIL/FLOOR.W.D are checked through the real CPU and selected system retire differential; configurable FCSR rounding modes, complete IEEE-754 edge cases and precise FPE delivery remain open |
| COP1 double-precision LDC1/SDC1 | partial, opt-in | `SOC_FPU_ENABLE=1`; even FPR pairs, ordered little-endian word beats, precise first/second beat hold and no partial load commit; bounded scheduler FPR/FCSR context transfer is covered by `fpu-context-gate`, while Linux signal-frame/lazy-FPU ABI remains open |
| COP1 IEEE-754 flags/traps, OS context and ABI | partial, opt-in | `fpu-fpe-exception-gate`, `fpu-fpe-invalid-gate`, `fpu-fpe-overflow-gate`, `fpu-fpe-underflow-gate`, `fpu-fpe-inexact-gate`, `fpu-fpe-double-inexact-gate`, `fpu-fpe-double-underflow-gate`, `mips-fpu-flags-gate`, and `fpu-context-gate` verify precise enabled single/double slices, sticky Flags/Cause, no FPR commit, and scheduler FPR/FCSR save/restore; QEMU's custom reference now retains accrued Flags on enabled FPE; complete underflow/inexact/range policy, full double FPE corpus, lazy-FPU/signal-frame ABI and Linux context semantics remain unimplemented |
| DSP/MDMX, EJTAG/debug, implementation-specific ASEs | deferred | outside frozen MIPS32 R2 CPU contract |

The audit gate checks that every row has a status and that the aggregate
report retains the explicit full-ISA residuals. It is an architecture audit,
not an ISA compliance claim.
