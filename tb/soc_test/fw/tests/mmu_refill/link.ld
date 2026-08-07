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

    /* Hardware-walker gate: physical root/L2 tables and backing pages are
     * emitted into the SRAM image at their kseg0 aliases. */
    .pt_root 0x80001000 : { KEEP(*(.pt_root)) } > SRAM
    .pt_l2   0x80002000 : { KEEP(*(.pt_l2)) } > SRAM
    .page_data 0x80006000 : { KEEP(*(.page_data)) } > SRAM

    .text : { *(.text .text.*) } > SRAM
    .rodata : { *(.rodata .rodata.*) } > SRAM
    .data : { *(.data .data.*) } > SRAM
    .bss : {
        __bss_start = .;
        *(.bss .bss.*) *(COMMON)
        __bss_end = .;
    } > SRAM
}
