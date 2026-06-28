import sys

def bin2hex(bin_file, hex_file):
    with open(bin_file, 'rb') as f:
        data = f.read()
    
    with open(hex_file, 'w') as f:
        # Write out 32-bit words in hex format
        for i in range(0, len(data), 4):
            word = data[i:i+4]
            # Pad with 0 if necessary
            if len(word) < 4:
                word += b'\x00' * (4 - len(word))
            
            # MIPS is usually big-endian, but let's check our SoC endianness. 
            # In our previous tests, it was Little Endian (as typical in PC simulation).
            # Assuming Little Endian (if it's BE, swap [::-1] or leave as is based on ABI)
            # Actually, standard mips-gcc builds big-endian by default unless -EL is passed.
            # We will configure gcc with -EL. So binary is LE.
            # A Verilog memory of 32-bit words needs the hex string matching [31:0]
            val = int.from_bytes(word, byteorder='little')
            f.write(f"{val:08x}\n")

if __name__ == '__main__':
    bin2hex(sys.argv[1], sys.argv[2])
