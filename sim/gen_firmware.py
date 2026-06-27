import struct

# Machine code instructions
instructions = [
    0x3c014000, # 0: lui $1, 0x4000
    0x3c020000, # 1: lui $2, 0x0000
    0x34420100, # 2: ori $2, $2, 0x0100
    0x90430000, # 3: loop: lbu $3, 0($2)
    0x10600003, # 4: beq $3, $0, +3 (jump to end)
    0xac230000, # 5: sw $3, 0($1)
    0x20420001, # 6: addi $2, $2, 1
    0x08000003, # 7: j loop
    0x08000008, # 8: end: j end
]

# The string to print
text = "Hello, SoC World!\n\0"
# Convert to bytes
text_bytes = text.encode('ascii')

# We need to output a file with 32-bit hex values per line.
# The memory is Word addressable in our readmemh.
# SRAM is RAM_SIZE = 16384 bytes = 4096 words.
words = [0] * 4096

# Load instructions
for i, inst in enumerate(instructions):
    words[i] = inst

# Load string at 0x0100 (which is word index 64)
# In my MIPS cpu, is it big-endian or little-endian?
# Let's pack as Big Endian since MIPS is usually Big Endian.
# We will check if it prints the right characters.
word_idx = 64
for i in range(0, len(text_bytes), 4):
    chunk = text_bytes[i:i+4]
    # Pad with zeros if necessary
    chunk = chunk + b'\0' * (4 - len(chunk))
    # Little Endian packing since addr_align == 00 maps to 7:0
    word = struct.unpack('<I', chunk)[0]
    words[word_idx] = word
    word_idx += 1

with open('firmware.hex', 'w') as f:
    for w in words:
        f.write(f"{w:08x}\n")

print("Generated firmware.hex")
