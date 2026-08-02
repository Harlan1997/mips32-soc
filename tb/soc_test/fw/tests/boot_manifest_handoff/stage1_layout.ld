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
        *(.text .text.*)
    } > BOOT_SRAM

    .rodata ALIGN(16) : {
        __runtime_rodata_start = .;
        KEEP(*(.rodata .rodata.*))
        __runtime_rodata_end = .;
    } > BOOT_SRAM

    .data ALIGN(16) : {
        __runtime_data_start = .;
        KEEP(*(.data .data.*))
        __runtime_data_end = .;
    } > BOOT_SRAM

    .bss ALIGN(16) (NOLOAD) : {
        __runtime_bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        __runtime_bss_end = .;
    } > BOOT_SRAM

    __runtime_stack_top = 0x80008000;
}
