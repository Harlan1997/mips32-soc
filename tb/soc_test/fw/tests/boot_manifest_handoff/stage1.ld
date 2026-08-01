OUTPUT_ARCH(mips)
ENTRY(stage1_entry)

MEMORY
{
    BOOT_SRAM (rwx) : ORIGIN = 0x80001000, LENGTH = 32K
}

SECTIONS
{
    . = ORIGIN(BOOT_SRAM);

    /DISCARD/ : {
        *(.note.gnu.build-id)
        *(.MIPS.abiflags)
        *(.reginfo)
    }

    .text.init : {
        KEEP(*(.text.init))
        *(.text*)
    } > BOOT_SRAM
}
