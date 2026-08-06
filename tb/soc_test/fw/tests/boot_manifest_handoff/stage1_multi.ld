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

    .text.init : { KEEP(*(.text.init)) } > BOOT_SRAM

    /* The loader uses these fixed physical source addresses after handoff. */
    .segment_table 0x80001800 : { KEEP(*(.segment_table)) } > BOOT_SRAM
    .segment_text 0x80001A00 : { KEEP(*(.segment_text)) } > BOOT_SRAM
    .segment_rodata 0x80001A20 : { KEEP(*(.segment_rodata)) } > BOOT_SRAM
    .segment_data 0x80001A24 : { KEEP(*(.segment_data)) } > BOOT_SRAM
}
