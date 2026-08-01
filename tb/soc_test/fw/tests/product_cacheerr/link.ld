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

    /* Product CacheErr vector selected while BEV=1. */
    .cache_error 0xBFC00100 : {
        KEEP(*(.cache_error))
    } > BOOT_ROM
}
