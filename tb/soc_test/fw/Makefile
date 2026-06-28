CC      = mips64-linux-gnu-gcc
OBJCOPY = mips64-linux-gnu-objcopy
CFLAGS  = -mabi=32 -mips32 -EL -O2 -ffreestanding -nostdlib -G 0 -mno-abicalls -fno-pic
LDFLAGS = -T link.ld -nostdlib

all: firmware.hex

firmware.elf: boot.s main.c
	$(CC) $(CFLAGS) $(LDFLAGS) boot.s main.c -o firmware.elf

firmware.bin: firmware.elf
	$(OBJCOPY) -O binary firmware.elf firmware.bin

firmware.hex: firmware.bin
	python3 elf2hex.py firmware.bin firmware.hex
	cp firmware.hex ../../../sim/firmware.hex

clean:
	rm -f *.elf *.bin *.hex
