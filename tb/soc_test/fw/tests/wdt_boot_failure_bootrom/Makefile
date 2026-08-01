TEST_NAME := wdt_boot_failure_bootrom
FW_TOP_DIR := ../..
CROSS_COMPILE ?= mips64-linux-gnu-
CC := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy
CFLAGS := -mabi=32 -mips32 -EL -O2 -ffreestanding -nostdlib -G 0 -mno-abicalls -fno-pic
OUT_DIR ?= .
FW_BASE ?= firmware

ELF := $(OUT_DIR)/boot_rom.elf
BIN := $(OUT_DIR)/boot_rom.bin
HEX := $(OUT_DIR)/boot_rom.hex

.PHONY: all clean

all: $(HEX)

$(OUT_DIR):
	mkdir -p $(OUT_DIR)

$(ELF): bootrom.s bootrom.ld | $(OUT_DIR)
	$(CC) $(CFLAGS) -T bootrom.ld -nostdlib -Wl,-Map,$(OUT_DIR)/boot_rom.map bootrom.s -o $@

$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@

$(HEX): $(BIN)
	python3 $(FW_TOP_DIR)/common/elf2hex.py $< $@

clean:
	rm -f $(ELF) $(BIN) $(HEX) $(OUT_DIR)/boot_rom.map
