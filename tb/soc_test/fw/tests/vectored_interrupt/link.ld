OUTPUT_ARCH(mips)
ENTRY(_start)

MEMORY
{
    BOOT_ROM (rx) : ORIGIN = 0xBFC00000, LENGTH = 64K
}

SECTIONS
{
    . = ORIGIN(BOOT_ROM);

    /DISCARD/ : {
        *(.note.gnu.build-id)
        *(.MIPS.abiflags)
        *(.reginfo)
    }

    .text.init : {
        KEEP(*(.text.init))
    } > BOOT_ROM

    /* The testbench mirrors this ROM image into Boot SRAM at PA 0, so the
     * BEV=0 EBase vector fetch has executable contents at PA 0x220. */
    .vectored_interrupt 0xBFC00220 : {
        KEEP(*(.vectored_interrupt))
    } > BOOT_ROM
}
