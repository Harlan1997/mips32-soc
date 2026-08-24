#!/usr/bin/env python3
"""Compare DMA architectural events; transport/poll timing is intentionally absent."""
import json
import sys

FIELDS = ("event", "ch", "err", "code", "level", "src", "dst", "len", "sg")

def load(path):
    out = []
    with open(path, encoding="ascii") as stream:
        for line_no, line in enumerate(stream, 1):
            if not line.strip():
                continue
            item = json.loads(line)
            normalized = dict(item)
            for field in FIELDS:
                normalized.setdefault(field, 0)
            if normalized["event"] in ("W1C", "IRQ"):
                for field in ("err", "code", "src", "dst", "len", "sg"):
                    normalized[field] = 0
            out.append(tuple(normalized[field] for field in FIELDS))
    return out

def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: compare_dma_events.py RTL.jsonl QEMU.jsonl")
    rtl, qemu = load(sys.argv[1]), load(sys.argv[2])
    if rtl != qemu:
        limit = min(len(rtl), len(qemu))
        for i in range(limit):
            if rtl[i] != qemu[i]:
                raise SystemExit(f"DMA_EVENT_CONTRACT_FAIL index={i} rtl={rtl[i]} qemu={qemu[i]}")
        raise SystemExit(f"DMA_EVENT_CONTRACT_FAIL length rtl={len(rtl)} qemu={len(qemu)}")
    if not rtl:
        raise SystemExit("DMA_EVENT_CONTRACT_FAIL empty event stream")
    print(f"DMA_EVENT_CONTRACT_PASS events={len(rtl)}")

if __name__ == "__main__":
    main()
