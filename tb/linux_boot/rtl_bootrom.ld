OUTPUT_ARCH(mips)
ENTRY(_start)

MEMORY
{
    BOOT_ROM (rx) : ORIGIN = 0xBFC00000, LENGTH = 64K
}

SECTIONS
{
    . = ORIGIN(BOOT_ROM);
    /DISCARD/ : { *(.MIPS.abiflags) *(.reginfo) *(.note.gnu.build-id) }
    .text : { KEEP(*(.text.init)) *(.text*) } > BOOT_ROM
}
