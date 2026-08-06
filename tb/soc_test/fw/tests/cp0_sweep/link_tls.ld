OUTPUT_ARCH(mips)
ENTRY(_start)

MEMORY
{
    SRAM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
}

SECTIONS
{
    . = ORIGIN(SRAM);
    /DISCARD/ : { *(.note.gnu.build-id) *(.MIPS.abiflags) *(.reginfo) }
    .text.init : { *(.text.init) } > SRAM
    .except 0x0180 : { *(.except_vector) } > SRAM
    .text : { *(.text .text.*) } > SRAM
    .rodata : { *(.rodata .rodata.*) } > SRAM
    .data : { *(.data .data.*) } > SRAM

    .tdata 0x00006000 : ALIGN(4) {
        __tls_start = .;
        *(.tdata .tdata.*)
        __tls_end = .;
    } > SRAM

    .tbss (NOLOAD) : ALIGN(4) {
        __tbss_start = .;
        *(.tbss .tbss.*)
        __tbss_end = .;
    } > SRAM

    .bss : {
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    } > SRAM
}
