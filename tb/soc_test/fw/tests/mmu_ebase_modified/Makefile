# Product-mode EBase/Modified exception proof. The image starts in Boot ROM
# and relocates its general-exception handler into SRAM before use.
TEST_NAME       := mmu_ebase_modified
TEST_SOURCES    := product_ebase_modified.s
FW_TOP_DIR      := ../..
CUSTOM_BOOT     := 1
LINKER_SCRIPT   := $(CURDIR)/link.ld
include $(FW_TOP_DIR)/common/Makefile.rules
