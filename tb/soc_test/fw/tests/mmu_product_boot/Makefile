# Minimal product-mode MMU boot proof. The image is linked for the Boot ROM
# kseg1 aperture and owns its reset/refill entry points.
TEST_NAME       := mmu_product_boot
TEST_SOURCES    := product_boot.s
FW_TOP_DIR      := ../..
CUSTOM_BOOT     := 1
LINKER_SCRIPT   := $(CURDIR)/link.ld
include $(FW_TOP_DIR)/common/Makefile.rules
