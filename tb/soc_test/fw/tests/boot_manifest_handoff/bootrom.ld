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
        *(.text*)
    } > BOOT_ROM

    .boot_exception ORIGIN(BOOT_ROM) + 0x380 : {
        KEEP(*(.boot_exception))
    } > BOOT_ROM
}
