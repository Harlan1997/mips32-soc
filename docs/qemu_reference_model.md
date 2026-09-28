# QEMU Reference Model

Status: verified for the declared QEMU Linux terminal workload on 2026-09-28.

## Identity

The project reference model is the custom QEMU machine named
`mips32-soc-ref`. It is a software behavioral model used as the QEMU baseline
for SoC contract checks and RTL differential work. It is not the RTL design and
it is not a production hardware model.

- Machine implementation: [`scripts/qemu/mips32_soc_ref.c`](../scripts/qemu/mips32_soc_ref.c)
- Build script: [`scripts/qemu/build_mips32_soc_ref.sh`](../scripts/qemu/build_mips32_soc_ref.sh)
- QEMU source tree: `/data/disk/tmp/mips32-soc/qemu-9.2.0`
- Verified executable: `/data/disk/tmp/mips32-soc/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel`
- Source SHA-256: `7b1225e250165a42e98d5e06f27b9642f3d44b75f931fcc7ffdecbf02b8bd2b1`
- Executable SHA-256: `da8dc0a4c91c6e87d7e0415a36f51dc696a2f97a2be076c4b4f63a40ff67d431`

The capture library `libqemu_retire.so` is an evidence plugin. It is not the
reference model itself.

## Verified Configuration

The passing run used:

```text
-M mips32-soc-ref,linux-guest=on
-cpu 24Kc
-accel tcg,thread=single
-m 64M
linux-rng-seed=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
```

The guest command line came from the validated DTB rather than a separate
override.

## Verified Inputs

- Kernel: `/data/disk/tmp/mips32-soc/full-qemu-marker-build/kernel/vmlinux`
- Image directory: `/data/disk/tmp/mips32-soc/full-qemu-marker-image`
- DTB: `mips32_soc_ref_rtl.dtb`
- Kernel SHA-256: `01857c8626f910f3c9fb0ec55cf0c53e44d001b6ecc8662b344b424049793682`
- DTB SHA-256: `cf58ab731c4adbe0889216141f22ac6dfe21c920f3ac8da716d81fad836a36cf`
- Image manifest SHA-256: `a8220506863d628a6333b832a704d8f55b9d3f16f69ab011fe9e83b0683ae8b5`
- Deterministic entropy seed ID: `a8ae6e6ee929abea3afcfc5258c8ccd6f85273e0d4626d26c7279f3250f77c8e`

## Verification Evidence

The authoritative run was launched through:

```bash
make qemu-system-linux-full-closure-gate \
  QEMU_BIN=/data/disk/tmp/mips32-soc/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel \
  QEMU_SRC=/data/disk/tmp/mips32-soc/qemu-9.2.0 \
  QEMU_BUILD=/data/disk/tmp/mips32-soc/qemu-9.2.0/build-mipsel-softmmu \
  KERNEL=/data/disk/tmp/mips32-soc/full-qemu-marker-build/kernel/vmlinux \
  LINUX_IMAGE_DIR=/data/disk/tmp/mips32-soc/full-qemu-marker-image
```

Run evidence is retained under:

`/data/disk/tmp/mips32-soc/qemu-linux-full-closure-v23/isa_ref/qemu_linux_full_closure/`

The run proved:

- `99,545,418` retired instructions through the terminal checkpoint;
- all 12 required Linux workload markers in order;
- exactly one `MIPS32_SOC_LINUX_TERMINAL` marker in stdout and modeled UART bytes;
- `terminal_marker=flushed` in `qemu/qemu_capture_status.txt`;
- valid deterministic image and tool hashes in `qemu_terminal_manifest.json`.

The compact evidence files are `completion_report.md`,
`qemu_terminal_manifest.json`, `marker_evidence.json`,
`qemu/qemu_stdout.log`, `qemu/qemu_capture_status.txt`, and
`qemu/peripheral.jsonl`.

## Scope Boundary

This record verifies the declared Linux workload on the QEMU reference model.
It does not prove RTL Linux userspace reachability, RTL/QEMU architectural
trace equality, full ISA or MMU compliance, or physical hardware behavior.
Those require the RTL producer and the deferred differential gate to reach the
same terminal boundary.
