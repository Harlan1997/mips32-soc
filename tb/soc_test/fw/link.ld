OUTPUT_ARCH(mips)
ENTRY(_start)

MEMORY
{
    SRAM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
    SPI  (rx)  : ORIGIN = 0x10000000, LENGTH = 16M
}

SECTIONS
{
    /* For simple tests, we put everything in SRAM to avoid flashing SPI first */
    . = ORIGIN(SRAM);

    /DISCARD/ : {
        *(.note.gnu.build-id)
        *(.MIPS.abiflags)
        *(.reginfo)
    }

    .text.init : {
        *(.text.init)
    } > SRAM


    .except 0x0180 : {
        *(.except_vector)
    } > SRAM

    .text : {
        *(.text .text.*)
    } > SRAM

    .rodata : {
        *(.rodata .rodata.*)
    } > SRAM

    .data : {
        *(.data .data.*)
    } > SRAM

    .bss : {
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    } > SRAM
}
