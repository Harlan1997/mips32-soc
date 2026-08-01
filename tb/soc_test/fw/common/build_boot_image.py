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


def image_with_word(image: bytes, word_offset: int, value: int) -> bytes:
    result = bytearray(image)
    struct.pack_into("<I", result, word_offset, value)
    return bytes(result)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--payload-bin", required=True, type=Path)
    parser.add_argument("--output-hex", required=True, type=Path)
    parser.add_argument("--bad-crc-hex", type=Path)
    parser.add_argument("--negative-dir", type=Path)
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
        write_byte_hex(args.bad_crc_hex, image_with_word(image, 0x20, crc32 ^ 0x01))

    if args.negative_dir:
        args.negative_dir.mkdir(parents=True, exist_ok=True)
        # Each image invalidates exactly one Boot ROM header check. This keeps
        # a preceding failure from hiding an untested validation branch.
        negative_images = {
            "bad_magic": image_with_word(image, 0x00, 0),
            "bad_version": image_with_word(image, 0x04, FORMAT_VERSION + 1),
            "bad_header_bytes": image_with_word(image, 0x08, HEADER_BYTES - 4),
            "bad_payload_offset": image_with_word(image, 0x0C, PAYLOAD_OFFSET + 4),
            "bad_payload_length_zero": image_with_word(image, 0x10, 0),
            "bad_payload_length_unaligned": image_with_word(image, 0x10, len(payload) - 1),
            "bad_payload_length_bounds": image_with_word(image, 0x10, 0x8004),
            "bad_load_address": image_with_word(image, 0x14, LOAD_PHYS_ADDR + 4),
            "bad_entry_address": image_with_word(image, 0x18, ENTRY_VIRT_ADDR + 4),
            "bad_flags": image_with_word(image, 0x1C, 0),
        }
        for name, negative_image in negative_images.items():
            write_byte_hex(args.negative_dir / f"{name}.hex", negative_image)


if __name__ == "__main__":
    main()
