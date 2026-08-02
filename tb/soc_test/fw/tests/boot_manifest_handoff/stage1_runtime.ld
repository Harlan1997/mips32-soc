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
    } > BOOT_SRAM

    .runtime_handler 0x800010A0 : {
        KEEP(*(.runtime_handler))
    } > BOOT_SRAM

    .runtime_main 0x80001100 : {
        KEEP(*(.runtime_main))
    } > BOOT_SRAM

    .rodata 0x800012C0 : {
        KEEP(*(.rodata .rodata.*))
    } > BOOT_SRAM

    .data 0x800012D0 : {
        KEEP(*(.data .data.*))
    } > BOOT_SRAM

    .bss 0x800012E0 (NOLOAD) : {
        KEEP(*(.bss .bss.*))
    } > BOOT_SRAM

    .runtime_reloc 0x80001300 : {
        KEEP(*(.runtime_reloc))
    } > BOOT_SRAM

    /* Keep the manifest payload size deterministic, including zero-filled
     * section gaps that are part of the relocation image. */
    .image_end 0x8000131C : {
        LONG(0)
    } > BOOT_SRAM
}
