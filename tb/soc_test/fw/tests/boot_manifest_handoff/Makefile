TEST_NAME := boot_manifest_handoff
FW_TOP_DIR := ../..
COMMON_DIR := $(FW_TOP_DIR)/common
CROSS_COMPILE ?= mips64-linux-gnu-
CC := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy

CFLAGS := -mabi=32 -mips32 -EL -O2 -ffreestanding -nostdlib -G 0 -mno-abicalls -fno-pic
OUT_DIR ?= .
FW_BASE ?= firmware

BOOT_ROM_ELF := $(OUT_DIR)/boot_rom.elf
BOOT_ROM_BIN := $(OUT_DIR)/boot_rom.bin
BOOT_ROM_HEX := $(OUT_DIR)/boot_rom.hex
STAGE1_ELF := $(OUT_DIR)/stage1.elf
STAGE1_BIN := $(OUT_DIR)/stage1.bin
STAGE1_HEX := $(OUT_DIR)/stage1.hex
STAGE1_DEPTH_ELF := $(OUT_DIR)/stage1_depth.elf
STAGE1_DEPTH_BIN := $(OUT_DIR)/stage1_depth.bin
STAGE1_DEPTH_HEX := $(OUT_DIR)/stage1_depth.hex
FLASH_IMAGE_HEX := $(OUT_DIR)/flash_image.hex
FLASH_IMAGE_BAD_CRC_HEX := $(OUT_DIR)/flash_image_bad_crc.hex
FLASH_IMAGE_DEPTH_HEX := $(OUT_DIR)/flash_image_depth.hex
NEGATIVE_DIR := $(OUT_DIR)/negative
NEGATIVE_IMAGES := $(addprefix $(NEGATIVE_DIR)/,bad_magic.hex bad_version.hex bad_header_bytes.hex bad_payload_offset.hex bad_payload_length_zero.hex bad_payload_length_unaligned.hex bad_payload_length_bounds.hex bad_load_address.hex bad_entry_address.hex bad_flags.hex)
MANIFEST := $(OUT_DIR)/$(FW_BASE).manifest

.PHONY: all depth toolchain-check clean

all: toolchain-check $(BOOT_ROM_HEX) $(STAGE1_HEX) $(FLASH_IMAGE_HEX) $(FLASH_IMAGE_BAD_CRC_HEX) $(NEGATIVE_IMAGES) $(MANIFEST)

depth: toolchain-check $(BOOT_ROM_HEX) $(STAGE1_DEPTH_HEX) $(FLASH_IMAGE_DEPTH_HEX)

toolchain-check:
	@command -v $(CC) >/dev/null || { \
		echo "ERROR: missing MIPS32 cross compiler: $(CC)"; exit 1; }

$(OUT_DIR):
	mkdir -p $(OUT_DIR)

$(BOOT_ROM_ELF): bootrom.s bootrom.ld | $(OUT_DIR)
	$(CC) $(CFLAGS) -T bootrom.ld -nostdlib -Wl,-Map,$(OUT_DIR)/boot_rom.map bootrom.s -o $@

$(BOOT_ROM_BIN): $(BOOT_ROM_ELF)
	$(OBJCOPY) -O binary $< $@

$(BOOT_ROM_HEX): $(BOOT_ROM_BIN)
	python3 $(COMMON_DIR)/elf2hex.py $< $@

$(STAGE1_ELF): stage1.s stage1.ld | $(OUT_DIR)
	$(CC) $(CFLAGS) -T stage1.ld -nostdlib -Wl,-Map,$(OUT_DIR)/stage1.map stage1.s -o $@

$(STAGE1_BIN): $(STAGE1_ELF)
	$(OBJCOPY) -O binary $< $@

$(STAGE1_HEX): $(STAGE1_BIN)
	python3 $(COMMON_DIR)/elf2hex.py $< $@

$(STAGE1_DEPTH_ELF): stage1_depth.s stage1.ld | $(OUT_DIR)
	$(CC) $(CFLAGS) -T stage1.ld -nostdlib -Wl,-Map,$(OUT_DIR)/stage1_depth.map stage1_depth.s -o $@

$(STAGE1_DEPTH_BIN): $(STAGE1_DEPTH_ELF)
	$(OBJCOPY) -O binary $< $@

$(STAGE1_DEPTH_HEX): $(STAGE1_DEPTH_BIN)
	python3 $(COMMON_DIR)/elf2hex.py $< $@

$(FLASH_IMAGE_HEX) $(FLASH_IMAGE_BAD_CRC_HEX) $(NEGATIVE_IMAGES): $(STAGE1_BIN) $(COMMON_DIR)/build_boot_image.py
	python3 $(COMMON_DIR)/build_boot_image.py --payload-bin $(STAGE1_BIN) --output-hex $(FLASH_IMAGE_HEX) --bad-crc-hex $(FLASH_IMAGE_BAD_CRC_HEX) --negative-dir $(NEGATIVE_DIR)

$(FLASH_IMAGE_DEPTH_HEX): $(STAGE1_DEPTH_BIN) $(COMMON_DIR)/build_boot_image.py
	python3 $(COMMON_DIR)/build_boot_image.py --payload-bin $(STAGE1_DEPTH_BIN) --output-hex $(FLASH_IMAGE_DEPTH_HEX)

$(MANIFEST): $(BOOT_ROM_HEX) $(STAGE1_HEX) $(FLASH_IMAGE_HEX) $(FLASH_IMAGE_BAD_CRC_HEX)
	@{ \
		echo "test_name=$(TEST_NAME)"; \
		sha256sum $(BOOT_ROM_HEX) $(STAGE1_HEX) $(FLASH_IMAGE_HEX) $(FLASH_IMAGE_BAD_CRC_HEX); \
	} > $@

clean:
	rm -f $(BOOT_ROM_ELF) $(BOOT_ROM_BIN) $(BOOT_ROM_HEX) $(OUT_DIR)/boot_rom.map \
		$(STAGE1_ELF) $(STAGE1_BIN) $(STAGE1_HEX) $(OUT_DIR)/stage1.map \
		$(STAGE1_DEPTH_ELF) $(STAGE1_DEPTH_BIN) $(STAGE1_DEPTH_HEX) $(OUT_DIR)/stage1_depth.map \
		$(FLASH_IMAGE_HEX) $(FLASH_IMAGE_BAD_CRC_HEX) $(FLASH_IMAGE_DEPTH_HEX) $(MANIFEST)
	rm -rf $(NEGATIVE_DIR)
