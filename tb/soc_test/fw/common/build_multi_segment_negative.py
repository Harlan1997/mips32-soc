#!/usr/bin/env python3
"""Create a valid-CRC multi-segment image with a W+X text descriptor."""

import argparse
import binascii
import struct
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-hex", required=True, type=Path)
    parser.add_argument("--output-hex", required=True, type=Path)
    args = parser.parse_args()
    image = bytearray(int(line.strip(), 16) for line in args.input_hex.read_text().splitlines() if line.strip())
    struct.pack_into("<I", image, 64 + 0x800 + 8 + 12, 0x6)
    struct.pack_into("<I", image, 0x20, binascii.crc32(image[64:]) & 0xFFFFFFFF)
    args.output_hex.write_text("".join(f"{value:02x}\n" for value in image), encoding="ascii")


if __name__ == "__main__":
    main()
