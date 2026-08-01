#!/usr/bin/env python3
"""Build a development flash image with the fixed SoC boot manifest."""

import argparse
import binascii
import struct
from pathlib import Path


MAGIC = 0x534F4331
FORMAT_VERSION = 1
HEADER_BYTES = 64
PAYLOAD_OFFSET = HEADER_BYTES
LOAD_PHYS_ADDR = 0x00001000
ENTRY_VIRT_ADDR = 0x80001000
DEVELOPMENT_CRC_FLAG = 0x00000001


def write_byte_hex(path: Path, image: bytes) -> None:
    path.write_text("".join(f"{value:02x}\n" for value in image), encoding="ascii")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--payload-bin", required=True, type=Path)
    parser.add_argument("--output-hex", required=True, type=Path)
    parser.add_argument("--bad-crc-hex", type=Path)
    args = parser.parse_args()

    payload = args.payload_bin.read_bytes()
    payload += bytes((-len(payload)) % 4)
    if not payload or len(payload) > 0x8000:
        raise SystemExit("payload must be a non-empty, word-aligned image no larger than 32 KiB")

    crc32 = binascii.crc32(payload) & 0xFFFFFFFF
    header = struct.pack(
        "<9I",
        MAGIC,
        FORMAT_VERSION,
        HEADER_BYTES,
        PAYLOAD_OFFSET,
        len(payload),
        LOAD_PHYS_ADDR,
        ENTRY_VIRT_ADDR,
        DEVELOPMENT_CRC_FLAG,
        crc32,
    )
    header += bytes(HEADER_BYTES - len(header))
    image = header + payload
    write_byte_hex(args.output_hex, image)

    if args.bad_crc_hex:
        corrupt = bytearray(image)
        corrupt[0x20] ^= 0x01
        write_byte_hex(args.bad_crc_hex, corrupt)


if __name__ == "__main__":
    main()
