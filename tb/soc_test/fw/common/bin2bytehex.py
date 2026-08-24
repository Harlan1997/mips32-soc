#!/usr/bin/env python3
"""Write one two-digit hex byte per line for a Verilog byte memory."""
import sys


def main():
    source, target = sys.argv[1:3]
    with open(source, "rb") as stream:
        data = stream.read()
    with open(target, "w", encoding="ascii") as stream:
        for value in data:
            stream.write(f"{value:02x}\n")


if __name__ == "__main__":
    main()
