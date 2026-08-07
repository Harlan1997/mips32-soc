OUTPUT_ARCH(mips)
ENTRY(_start)

MEMORY
{
    SRAM (rwx) : ORIGIN = 0x80000000, LENGTH = 64K
}

SECTIONS
{
    . = ORIGIN(SRAM);

    /DISCARD/ : {
        *(.note.gnu.build-id)
        *(.MIPS.abiflags)
        *(.reginfo)
    }

    .text.init : { KEEP(*(.text.init)) } > SRAM

    .except 0x80000180 : { KEEP(*(.except_vector)) } > SRAM

    .text : { *(.text .text.*) } > SRAM
    .rodata : { *(.rodata .rodata.*) } > SRAM
    .data : { *(.data .data.*) } > SRAM
    .bss : {
        __bss_start = .;
        *(.bss .bss.*) *(COMMON)
        __bss_end = .;
    } > SRAM
}
