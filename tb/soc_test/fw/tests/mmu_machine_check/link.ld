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
    .text.init : { KEEP(*(.text.init)) } > BOOT_ROM
    .runtime_general_handler 0xBFC00400 : {
        _runtime_general_handler = .;
        KEEP(*(.runtime_general_handler))
        _runtime_general_handler_end = .;
    } > BOOT_ROM
}
