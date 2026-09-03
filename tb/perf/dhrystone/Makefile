ROOT_DIR ?= $(abspath ../../..)
OUT_DIR ?= $(ROOT_DIR)/build/perf/dhrystone
CROSS_COMPILE ?= mips64-linux-gnu-
CC := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump
COMMON := $(ROOT_DIR)/tb/soc_test/fw/common

CFLAGS := -mabi=32 -mips32 -EL -O2 -ffreestanding -nostdlib -G 0 \
           -mno-abicalls -fno-pic -fno-builtin -DTIME \
           -DSOC_DHRY_BAREMETAL=1 -DDHRY_RUNS=100 -I. -I$(COMMON)
LDFLAGS := -T $(COMMON)/link.ld -nostdlib -Wl,-Map,$(OUT_DIR)/dhrystone.map
SOURCES := $(COMMON)/boot.s $(COMMON)/excpt.c $(COMMON)/print.c \
           dhry_1.c dhry_2.c dhrystone_port.c

.PHONY: all clean
all: $(OUT_DIR)/firmware.hex

$(OUT_DIR):
	mkdir -p $(OUT_DIR)

$(OUT_DIR)/firmware.elf: $(SOURCES) dhry.h dhrystone_port.h | $(OUT_DIR)
	$(CC) $(CFLAGS) $(SOURCES) $(LDFLAGS) -o $@

$(OUT_DIR)/firmware.bin: $(OUT_DIR)/firmware.elf
	$(OBJCOPY) -O binary $< $@

$(OUT_DIR)/firmware.hex: $(OUT_DIR)/firmware.bin
	python3 $(COMMON)/elf2hex.py $< $@
	$(OBJDUMP) -d -S $(OUT_DIR)/firmware.elf > $(OUT_DIR)/firmware.objdump

clean:
	$(RM) $(OUT_DIR)/firmware.elf $(OUT_DIR)/firmware.bin $(OUT_DIR)/firmware.hex
