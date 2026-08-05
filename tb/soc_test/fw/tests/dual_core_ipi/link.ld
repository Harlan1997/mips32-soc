OUTPUT_ARCH(mips)
ENTRY(_start)
MEMORY { SRAM (rx) : ORIGIN = 0x00000000, LENGTH = 64K }
SECTIONS {
  . = ORIGIN(SRAM);
  /DISCARD/ : { *(.note.gnu.build-id) *(.MIPS.abiflags) *(.reginfo) }
  .text : { *(.text) } > SRAM
}
