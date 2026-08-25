#!/usr/bin/env python3
"""Compare the observable dual-mailbox IPI contract in RTL and QEMU traces."""
import json
import sys

REGS = {"4000a020", "4000a024", "4000a028", "4000a02c", "4000a030", "4000a034", "4000a038", "4000a03c"}

def records(path):
    with open(path, encoding="ascii") as stream:
        return [json.loads(line) for line in stream if line.strip()]

def writes(items):
    result = []
    for item in items:
        addr = item.get("mem_addr", "").lower()
        if item.get("mem_valid") and item.get("mem_write") and addr in REGS:
            # W1C writes contain the producer's observed sticky status. The
            # exact mask is timing-dependent, while the other control writes
            # are part of the architectural request sequence.
            data = item.get("mem_wdata", "").lower()
            if addr == "4000a038":
                data = "W1C"
            result.append((addr, data))
    return result

def status_bits(items):
    result = set()
    for item in items:
        if (item.get("mem_valid") and item.get("mem_read") and
                item.get("mem_addr", "").lower() == "4000a034"):
            value = int(item.get("mem_rdata", "0"), 16)
            result.add(value & 0x3c)
    return result

def main():
    if len(sys.argv) != 3:
        print("usage: compare_mmu_ipi_contract.py RTL QEMU", file=sys.stderr)
        return 2
    rtl = records(sys.argv[1])
    qemu = records(sys.argv[2])
    rtl_writes, qemu_writes = writes(rtl), writes(qemu)
    if rtl_writes != qemu_writes:
        print("IPI_CONTRACT_COMPARE_FAIL: control write sequence differs")
        print("RTL:", rtl_writes)
        print("QEMU:", qemu_writes)
        return 1
    for name, items in (("RTL", rtl), ("QEMU", qemu)):
        observed = status_bits(items)
        if not any(bits & (1 << 2) for bits in observed):
            print(f"IPI_CONTRACT_COMPARE_FAIL: {name} lacks done")
            return 1
        if not any(bits & (1 << 3) for bits in observed):
            print(f"IPI_CONTRACT_COMPARE_FAIL: {name} lacks timeout")
            return 1
        if not any(bits & (1 << 4) for bits in observed):
            print(f"IPI_CONTRACT_COMPARE_FAIL: {name} lacks rejected")
            return 1
        if not any(bits & (1 << 5) for bits in observed):
            print(f"IPI_CONTRACT_COMPARE_FAIL: {name} lacks stale-ack")
            return 1
    print(f"IPI_CONTRACT_COMPARE_PASS writes={len(rtl_writes)}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
