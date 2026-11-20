#!/usr/bin/env python3
"""Constrained-random MIPS32 Release 2 ISA program generator for RTL-vs-QEMU differential testing."""

import argparse
import os
import random

# Safe GPR pool (avoid $0, $at=$1, $k0=$26, $k1=$27, $sp=$29, $ra=$31, and $s0=$16 base pointer)
GPRS = [
    "$v0", "$v1",
    "$a0", "$a1", "$a2", "$a3",
    "$t0", "$t1", "$t2", "$t3", "$t4", "$t5", "$t6", "$t7",
    "$s1", "$s2", "$s3", "$s4", "$s5", "$s6", "$s7",
    "$t8", "$t9",
]


def reg(rng: random.Random) -> str:
    return rng.choice(GPRS)


def generate_program(seed: int, count: int) -> str:
    rng = random.Random(seed)
    lines = [
        "    .set noreorder",
        "    .set noat",
        "    .section .text.init",
        "    .globl _start",
        "_start:",
        "    /* Seed GPRs deterministically */",
    ]
    for idx, r in enumerate(GPRS):
        hi = rng.randint(0, 0xFFFF)
        lo = rng.randint(0, 0xFFFF)
        lines.append(f"    lui   {r}, 0x{hi:04x}")
        lines.append(f"    ori   {r}, {r}, 0x{lo:04x}")

    # Scratch data base in $s0 (within SRAM .bss/.data region)
    lines += [
        "    lui   $s0, %hi(scratch_buf)",
        "    ori   $s0, $s0, %lo(scratch_buf)",
        "    mtlo  $t0",
        "    mthi  $t1",
        "    /* Constrained-random MIPS32 R2 instruction stream */",
    ]

    lbl_id = 0
    for i in range(count):
        kind = rng.choices(
            ["alu_r", "alu_i", "shift", "r2_bit", "mdu", "branch", "mem"],
            weights=[24, 20, 14, 14, 8, 8, 12],
        )[0]
        rd, rs, rt = reg(rng), reg(rng), reg(rng)
        imm16 = rng.randint(0, 0xFFFF)
        simm16 = rng.randint(-32768, 32767)
        sa = rng.randint(0, 31)

        if kind == "alu_r":
            op = rng.choice(["addu", "subu", "and", "or", "xor", "nor", "slt", "sltu"])
            lines.append(f"    {op:<6s} {rd}, {rs}, {rt}")
        elif kind == "alu_i":
            op = rng.choice(["addiu", "slti", "sltiu"])
            if op == "addiu":
                lines.append(f"    addiu  {rd}, {rs}, {simm16}")
            else:
                lines.append(f"    {op:<6s} {rd}, {rs}, {simm16}")
            if rng.random() < 0.35:
                lop = rng.choice(["andi", "ori", "xori"])
                lines.append(f"    {lop:<6s} {rd}, {rs}, 0x{imm16:04x}")
        elif kind == "shift":
            if rng.random() < 0.6:
                op = rng.choice(["sll", "srl", "sra", "rotr"])
                lines.append(f"    {op:<6s} {rd}, {rt}, {sa}")
            else:
                op = rng.choice(["sllv", "srlv", "srav", "rotrv"])
                lines.append(f"    {op:<6s} {rd}, {rt}, {rs}")
        elif kind == "r2_bit":
            sub = rng.choice(["seb", "seh", "wsbh", "clz", "clo", "ext", "ins"])
            if sub in ("seb", "seh", "wsbh", "clz", "clo"):
                lines.append(f"    {sub:<6s} {rd}, {rt}")
            elif sub == "ext":
                pos = rng.randint(0, 31)
                size = rng.randint(1, 32 - pos)
                lines.append(f"    ext    {rd}, {rs}, {pos}, {size}")
            else:
                pos = rng.randint(0, 31)
                size = rng.randint(1, 32 - pos)
                lines.append(f"    ins    {rd}, {rs}, {pos}, {size}")
        elif kind == "mdu":
            op = rng.choice(["mult", "multu", "madd", "msub", "mul"])
            if op == "mul":
                lines.append(f"    mul    {rd}, {rs}, {rt}")
            else:
                lines.append(f"    {op:<6s} {rs}, {rt}")
            if rng.random() < 0.5:
                lines.append(f"    mfhi   {rd}")
            else:
                lines.append(f"    mflo   {rd}")
        elif kind == "branch":
            lbl = f"br_skip_{lbl_id}"
            lbl_id += 1
            bop = rng.choice(["beq", "bne", "blez", "bgtz", "bltz", "bgez"])
            d_rd, d_rs, d_rt = reg(rng), reg(rng), reg(rng)
            if bop in ("beq", "bne"):
                lines.append(f"    {bop:<6s} {rs}, {rt}, {lbl}")
            else:
                lines.append(f"    {bop:<6s} {rs}, {lbl}")
            lines.append(f"    addu   {d_rd}, {d_rs}, {d_rt}")
            lines.append(f"    xori   {d_rd}, {d_rd}, 0x{rng.randint(0, 0xffff):04x}")
            lines.append(f"{lbl}:")
        elif kind == "mem":
            mop = rng.choice(["sw", "lw", "sh", "lh", "lhu", "sb", "lb", "lbu", "swl", "swr", "lwl", "lwr"])
            if mop in ("sw", "lw"):
                off = rng.randrange(0, 256, 4)
            elif mop in ("sh", "lh", "lhu"):
                off = rng.randrange(0, 256, 2)
            else:
                off = rng.randrange(0, 256, 1)
            lines.append(f"    {mop:<6s} {rt}, {off}($s0)")

    lines += [
        "    /* Standard differential completion mailbox */",
        "    lui   $t0, 0xa000",
        "    ori   $t0, $t0, 0xfffc",
        "    lui   $t1, 0xdead",
        "    ori   $t1, $t1, 0xbeef",
        "    sw    $t1, 0($t0)",
        "1:",
        "    b     1b",
        "    nop",
        "",
        "    .section .data",
        "    .align 4",
        "scratch_buf:",
        "    .space 256",
        "",
    ]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--count", type=int, default=200)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write(generate_program(args.seed, args.count))


if __name__ == "__main__":
    main()
