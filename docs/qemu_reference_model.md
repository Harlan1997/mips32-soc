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

## Source Acquisition and Rebuild

The project is pinned to QEMU 9.2.0. Use the official QEMU distribution page
or upstream repository for source provenance:

- [QEMU downloads](https://www.qemu.org/download/)
- [QEMU upstream repository](https://gitlab.com/qemu-project/qemu)
- [QEMU 9.2.0 source archive](https://download.qemu.org/qemu-9.2.0.tar.xz)
- [QEMU 9.2.0 archive signature](https://download.qemu.org/qemu-9.2.0.tar.xz.sig)

The build scripts apply project-local source changes to the QEMU tree. Start
with a fresh extraction when changing QEMU versions or recovering from a
partially interrupted build. The archive is the reproducible source input;
record its local digest before building:

```bash
mkdir -p build/deps/src
curl -fL \
  -o build/deps/qemu-9.2.0.tar.xz \
  https://download.qemu.org/qemu-9.2.0.tar.xz
curl -fL \
  -o build/deps/qemu-9.2.0.tar.xz.sig \
  https://download.qemu.org/qemu-9.2.0.tar.xz.sig
sha256sum build/deps/qemu-9.2.0.tar.xz
tar -xf build/deps/qemu-9.2.0.tar.xz -C build/deps/src
```

The signature is supplied for optional GPG verification using the QEMU
release-key instructions. The project does not embed an independently
verified archive checksum here; do not substitute a locally observed digest
for an upstream release record.

### Patch Format and Recovery

The project patches are Git/GNU unified diffs. The optional text after the
second `@@` in a hunk header is a section heading and is valid diff syntax:

```text
@@ -old_start,old_count +new_start,new_count @@ optional section heading
```

Every hunk body line must start with a space, `+`, or `-` (apart from the
standard `\ No newline at end of file` marker), and the declared counts must
match the body. The QEMU build helper checks and applies each project patch
with `git apply --check --no-index --recount` followed by the same apply
operation. `--recount` recalculates stale hunk counts; it cannot repair a
missing line prefix, incorrect context, or a patch applied to the wrong QEMU
version.

If a patch check fails, stop using that QEMU source tree. It may contain a
partial patch from an interrupted build or changes from the other QEMU target.
Re-extract the official 9.2.0 archive and retry. Do not mix system-mode and
linux-user modifications in one source tree. A fresh source tree is the
recovery boundary; a fresh build directory alone is not sufficient.

### Host Prerequisites

The host must provide a C toolchain and the normal QEMU build tools: Python 3,
Meson, Ninja, `pkg-config`, and the GLib development headers. The repository
scripts additionally use `git`, `ripgrep`, Perl, `sed`, `flock`, `sha256sum`,
`install`, `curl`, and `tar`. On Debian/Ubuntu, these are commonly supplied
by packages such as `build-essential`, `ninja-build`, `meson`, `pkg-config`,
`python3`, `libglib2.0-dev`, `libpixman-1-dev`, `zlib1g-dev`, `git`, `ripgrep`,
and `perl`; package names vary by distribution. `--enable-fdt=disabled` is
intentional in the project build, so libfdt is not required for these targets.

### System-Mode Build

Build the custom `mips32-soc-ref` machine and its QEMU system executable from
the repository root:

```bash
QEMU_SRC="$PWD/build/deps/src/qemu-9.2.0" \
QEMU_BUILD="$PWD/build/deps/src/qemu-9.2.0/build-mipsel-softmmu" \
QEMU_BUILD_JOBS="$(nproc)" \
make qemu-system-mips32-soc-ref
```

The result is:

```text
build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel
```

The script copies the project machine, UART timing header, and GDB XML into
the QEMU source tree and applies the patches under
[`scripts/qemu/patches`](../scripts/qemu/patches). It configures QEMU with
`mipsel-softmmu`, plugins enabled, `--disable-werror`, and FDT disabled.

### Linux-User Build

For the user-mode ISA reference harness, use a separate fresh source tree and
build directory. The linux-user script adds target-specific compatibility
guards to the QEMU source, so sharing only the source tree while separating
build directories is not sufficient:

```bash
mkdir -p build/deps/src/qemu-9.2.0-linux-user
tar --strip-components=1 \
  -xf build/deps/qemu-9.2.0.tar.xz \
  -C build/deps/src/qemu-9.2.0-linux-user
QEMU_SRC="$PWD/build/deps/src/qemu-9.2.0-linux-user" \
QEMU_BUILD="$PWD/build/deps/src/qemu-9.2.0-linux-user/build-mipsel-linux-user" \
make qemu-linux-user
```

The result is:

```text
build/deps/src/qemu-9.2.0-linux-user/build-mipsel-linux-user/qemu-mipsel
```

This target configures `mipsel-linux-user` and applies the Linux-user
compatibility adjustments required by the project. It is a separate binary
from the system-mode `qemu-system-mipsel`.

### Build Verification

Check the executable version and confirm that the custom machine was linked:

```bash
build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel --version
build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel \
  -M help | grep mips32-soc-ref
build/deps/src/qemu-9.2.0-linux-user/build-mipsel-linux-user/qemu-mipsel \
  --version
```

These commands verify build readiness only. A differential or Linux closure
run still needs the matching guest ELF/kernel, DTB, image directory, RTL
build, traces, and (where used) a freshly built capture plugin.

### Running on Another Server

Rebuilding on the destination server from the same repository commit and the
same QEMU 9.2.0 archive is the recommended portable workflow. Extract a new
source tree for each target (`mipsel-softmmu` and `mipsel-linux-user`). The
custom machine is not part of an unmodified upstream QEMU binary, so copying
only `qemu-system-mipsel` is not a complete reproducibility package. A copied
binary may also fail when the destination has a different host architecture,
libc, or required shared libraries.

For a gate run, provide destination-local paths explicitly, for example:

```bash
QEMU_SRC="$PWD/build/deps/src/qemu-9.2.0" \
QEMU_BUILD="$PWD/build/deps/src/qemu-9.2.0/build-mipsel-softmmu" \
QEMU_BIN="$PWD/build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel" \
KERNEL="$PWD/path/to/vmlinux" \
LINUX_IMAGE_DIR="$PWD/path/to/image-dir" \
make qemu-system-linux-full-closure-gate
```

The kernel, DTB, rootfs/image manifest, boot ROM or firmware, and any QSPI
image must be transferred or rebuilt as matching artifacts. Differential
gates also generate or require their project-local plugin and trace outputs;
those outputs are workload- and commit-specific, not supplied by QEMU itself.
Some older focused runner defaults still contain the historical `/data/disk`
path, so set `QEMU_BIN` explicitly when using those runners on another host.

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
