OUTPUT_ARCH(mips)
ENTRY(_start)

MEMORY
{
    BOOT_ROM (rx) : ORIGIN = 0xBFC00000, LENGTH = 64K
}

SECTIONS
{
    . = ORIGIN(BOOT_ROM);
    /DISCARD/ : { *(.note.gnu.build-id) *(.MIPS.abiflags) *(.reginfo) }
    .text.init : { KEEP(*(.text.init)) } > BOOT_ROM
    .tlb_refill 0xBFC00200 : { KEEP(*(.tlb_refill)) } > BOOT_ROM
}
