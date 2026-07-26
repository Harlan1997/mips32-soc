# Linux Boot Regression (Phase F)

Placeholder for U-Boot → Linux kernel → busybox rootfs boot regression, run
nightly against the DUT starting from QSPI Flash reset.

## Boot flow (target)

```
Reset  →  BootROM       (mask ROM, verifies QSPI header, jumps to SPL)
       →  SPL           (loads U-Boot proper from QSPI to DDR)
       →  U-Boot proper (initializes DDR, GMAC, storage; loads kernel)
       →  Linux kernel  (arch/mips/bcm47xx-like port)
       →  busybox init
       →  shell prompt  (marker for regression success)
```

## Dependencies (from other phases)

| Phase | Blocking dependency |
|---|---|
| Phase B | Full R2 ISA + MMU + precise exceptions |
| Phase C | Multi-outstanding AXI + L2 cache (perf floor) |
| Phase D | Real QSPI XIP, DDR3 controller, UART 16550, GMAC (optional for boot), Timer |
| Phase E | Multi-clock domain, proper reset sequence |

Linux boot **cannot** run until all four above phases have working
implementations of the marked components. This directory is a scaffold —
actual boot scripts arrive once Phase D DDR3 + QSPI controllers pass their
block-level UVM tests.

## Directory layout (planned)

```
tb/linux_boot/
  README.md                      ← this file
  bootrom/
    Makefile
    boot.S                       ← minimal mask-ROM
  uboot/
    (patched U-Boot source ref)
    build.sh
  kernel/
    (kernel source ref, config)
    build.sh
  rootfs/
    busybox.config
    init
  qspi_image_builder.py          ← packs bootrom+uboot+kernel+dtb into QSPI hex
  regress.sh                     ← runs simv, greps for shell prompt
  vcs_boot_top.sv                ← top wrapper for boot regression
```

## Success criteria

- `regress.sh` returns 0 → boot reached shell prompt → REGRESSION_BOOT_SUCCESS
- Time budget: ≤ 6 hours per boot run in simulation (initial target)
- 100 consecutive nightly boots pass → cleared for tape-out sign-off input
