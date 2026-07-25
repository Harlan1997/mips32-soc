CROSS_COMPILE ?= mips64-linux-gnu-
CC      = $(CROSS_COMPILE)gcc
OBJCOPY = $(CROSS_COMPILE)objcopy
OBJDUMP = $(CROSS_COMPILE)objdump
CFLAGS  = -mabi=32 -mips32 -EL -O2 -ffreestanding -nostdlib -G 0 -mno-abicalls -fno-pic
LDFLAGS = -T link.ld -nostdlib
OUT_DIR ?= .
FW_BASE ?= firmware

ELF      = $(OUT_DIR)/$(FW_BASE).elf
BIN      = $(OUT_DIR)/$(FW_BASE).bin
HEX      = $(OUT_DIR)/$(FW_BASE).hex
MAP      = $(OUT_DIR)/$(FW_BASE).map
OBJDUMP_OUT = $(OUT_DIR)/$(FW_BASE).objdump
MANIFEST = $(OUT_DIR)/$(FW_BASE).manifest
SOURCES  = boot.s main.c link.ld

.PHONY: all toolchain-check clean

all: toolchain-check $(HEX) $(OBJDUMP_OUT) $(MANIFEST)

toolchain-check:
	@command -v $(CC) >/dev/null || { \
		echo "ERROR: missing MIPS32 cross compiler: $(CC)"; \
		echo "Set CROSS_COMPILE=<prefix> or CC/OBJCOPY/OBJDUMP to the installed toolchain."; \
		exit 1; \
	}
	@command -v $(OBJCOPY) >/dev/null || { \
		echo "ERROR: missing MIPS objcopy: $(OBJCOPY)"; \
		exit 1; \
	}
	@command -v $(OBJDUMP) >/dev/null || { \
		echo "ERROR: missing MIPS objdump: $(OBJDUMP)"; \
		exit 1; \
	}

$(OUT_DIR):
	mkdir -p $(OUT_DIR)

$(ELF): $(SOURCES) | $(OUT_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) -Wl,-Map,$(MAP) boot.s main.c -o $(ELF)

$(BIN): $(ELF)
	$(OBJCOPY) -O binary $(ELF) $(BIN)

$(HEX): $(BIN)
	python3 elf2hex.py $(BIN) $(HEX)

$(OBJDUMP_OUT): $(ELF)
	$(OBJDUMP) -d -S $(ELF) > $(OBJDUMP_OUT)

$(MANIFEST): $(HEX) $(OBJDUMP_OUT)
	@{ \
		echo "fw_base=$(FW_BASE)"; \
		echo "out_dir=$(OUT_DIR)"; \
		echo "cc=$$($(CC) --version | head -n 1)"; \
		echo "objcopy=$$($(OBJCOPY) --version | head -n 1)"; \
		echo "objdump=$$($(OBJDUMP) --version | head -n 1)"; \
		sha256sum $(SOURCES) $(ELF) $(BIN) $(HEX) $(MAP) $(OBJDUMP_OUT); \
	} > $(MANIFEST)

clean:
	rm -f $(ELF) $(BIN) $(HEX) $(MAP) $(OBJDUMP_OUT) $(MANIFEST)
