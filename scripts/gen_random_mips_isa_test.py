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

EVEN_FPRS = [f"$f{i}" for i in range(0, 16, 2)]


def reg(rng: random.Random) -> str:
    return rng.choice(GPRS)


def generate_program(seed: int, count: int, enable_exceptions: bool = True, enable_fpu: bool = False) -> str:
    rng = random.Random(seed)
    lines = [
        "    .set noreorder",
        "    .set noat",
        "    .section .text.init",
        "    .globl _start",
        "_start:",
    ]
    if enable_fpu:
        lines += [
            "    lui   $t0, 0x2000            /* Status.CU1=1, BEV=0 */",
            "    mtc0  $t0, $12",
        ]
    else:
        lines += [
            "    mtc0  $zero, $12             /* Status.BEV=0 */",
        ]
    lines += [
        "    ehb",
        "    j     rand_main",
        "    nop",
        "",
        "    .section .except_vector, \"ax\"",
        "    .align 2",
        "    .globl _except_handler",
        "_except_handler:",
        "    mfc0  $k0, $13",
        "    mfc0  $k1, $14",
        "    addiu $k1, $k1, 4",
        "    mtc0  $k1, $14",
        "    ehb",
        "    eret",
        "    nop",
        "",
        "    .section .text",
        "    .align 2",
        "rand_main:",
        "    /* Seed GPRs deterministically */",
    ]
    for r in GPRS:
        hi = rng.randint(0, 0xFFFF)
        lo = rng.randint(0, 0xFFFF)
        lines.append(f"    lui   {r}, 0x{hi:04x}")
        lines.append(f"    ori   {r}, {r}, 0x{lo:04x}")

    # Scratch data base in $s0 (within SRAM .data region, 8-byte aligned)
    lines += [
        "    lui   $s0, %hi(scratch_buf)",
        "    ori   $s0, $s0, %lo(scratch_buf)",
        "    mtlo  $t0",
        "    mthi  $t1",
    ]
    if enable_fpu:
        lines += [
            "    ctc1  $zero, $31",
        ]
        for fr in EVEN_FPRS:
            r = reg(rng)
            lines.append(f"    mtc1  {r}, {fr}")
        lines.append("    ehb")

    lines.append("    /* Constrained-random MIPS32 R2 instruction stream */")

    kinds = ["alu_r", "alu_i", "shift", "r2_bit", "mdu", "branch", "mem", "barrier"]
    weights = [20, 16, 12, 12, 8, 8, 12, 4]
    if enable_exceptions:
        kinds.append("trap_exc")
        weights.append(8)
    if enable_fpu:
        kinds.append("fpu")
        weights.append(16)

    lbl_id = 0
    for _ in range(count):
        kind = rng.choices(kinds, weights=weights)[0]
        rd, rs, rt = reg(rng), reg(rng), reg(rng)
        imm16 = rng.randint(0, 0xFFFF)
        simm16 = rng.randint(-32768, 32767)
        sa = rng.randint(0, 31)

        if kind == "alu_r":
            op = rng.choice(["addu", "subu", "and", "or", "xor", "nor", "slt", "sltu"])
            lines.append(f"    {op:<6s} {rd}, {rs}, {rt}")
        elif kind == "alu_i":
            op = rng.choice(["addiu", "slti", "sltiu"])
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
            else:
                pos = rng.randint(0, 31)
                size = rng.randint(1, 32 - pos)
                lines.append(f"    {sub:<6s} {rd}, {rs}, {pos}, {size}")
        elif kind == "mdu":
            op = rng.choice(["mult", "multu", "madd", "msub", "mul"])
            if op == "mul":
                lines.append(f"    mul    {rd}, {rs}, {rt}")
            else:
                lines.append(f"    {op:<6s} {rs}, {rt}")
                lines.append(f"    {rng.choice(['mfhi', 'mflo']):<6s} {rd}")
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
        elif kind == "barrier":
            b = rng.choice(["sync 0", "sync 16", "pref 0, 0($s0)", "synci 0($s0)"])
            lines.append(f"    {b}")
        elif kind == "trap_exc":
            sub = rng.choice(["syscall", "break", "ov_add", "ov_sub", "ov_addi", "trap_r", "trap_i"])
            if sub == "syscall":
                lines.append(f"    syscall {rng.randint(0, 63)}")
            elif sub == "break":
                lines.append(f"    break  {rng.randint(0, 63)}")
            elif sub == "ov_add":
                lines.append(f"    add    {rd}, {rs}, {rt}")
            elif sub == "ov_sub":
                lines.append(f"    sub    {rd}, {rs}, {rt}")
            elif sub == "ov_addi":
                lines.append(f"    addi   {rd}, {rs}, {simm16}")
            elif sub == "trap_r":
                top = rng.choice(["teq", "tne", "tge", "tgeu", "tlt", "tltu"])
                lines.append(f"    {top:<6s} {rs}, {rt}, {rng.randint(0, 31)}")
            else:
                top = rng.choice(["teqi", "tnei", "tgei", "tgeiu", "tlti", "tltiu"])
                lines.append(f"    {top:<6s} {rs}, {simm16}")
        elif kind == "fpu":
            fd, fs, ft = rng.choice(EVEN_FPRS), rng.choice(EVEN_FPRS), rng.choice(EVEN_FPRS)
            fsub = rng.choice(["arith_s", "arith_d", "mem", "cmp_br", "rm"])
            if fsub == "arith_s":
                fop = rng.choice(["add.s", "sub.s", "mul.s", "abs.s", "neg.s", "mov.s"])
                if fop in ("abs.s", "neg.s", "mov.s"):
                    lines.append(f"    {fop:<6s} {fd}, {fs}")
                else:
                    lines.append(f"    {fop:<6s} {fd}, {fs}, {ft}")
            elif fsub == "arith_d":
                fop = rng.choice(["add.d", "sub.d", "mul.d", "abs.d", "neg.d", "mov.d"])
                if fop in ("abs.d", "neg.d", "mov.d"):
                    lines.append(f"    {fop:<6s} {fd}, {fs}")
                else:
                    lines.append(f"    {fop:<6s} {fd}, {fs}, {ft}")
            elif fsub == "mem":
                fmop = rng.choice(["swc1", "lwc1", "sdc1", "ldc1"])
                off = rng.randrange(0, 256, 8) if fmop in ("sdc1", "ldc1") else rng.randrange(0, 256, 4)
                lines.append(f"    {fmop:<6s} {ft}, {off}($s0)")
            elif fsub == "cmp_br":
                lbl = f"fbr_skip_{lbl_id}"
                lbl_id += 1
                cop = rng.choice(["c.eq.s", "c.lt.s", "c.le.s", "c.eq.d", "c.lt.d"])
                bop = rng.choice(["bc1t", "bc1f"])
                lines.append(f"    {cop:<6s} {fs}, {ft}")
                lines.append(f"    {bop:<6s} {lbl}")
                lines.append(f"    addiu  {rd}, {rs}, 1")
                lines.append(f"{lbl}:")
            else:
                rm = rng.randint(0, 3)
                lines.append(f"    ori    {rt}, $zero, {rm}")
                lines.append(f"    ctc1   {rt}, $31")
                lines.append(f"    cfc1   {rd}, $31")

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
        "    .align 3",
        "scratch_buf:",
        "    .space 256",
        "",
    ]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--count", type=int, default=200)
    parser.add_argument("--no-exceptions", action="store_true")
    parser.add_argument("--enable-fpu", action="store_true")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write(
            generate_program(
                args.seed,
                args.count,
                enable_exceptions=not args.no_exceptions,
                enable_fpu=args.enable_fpu,
            )
        )


if __name__ == "__main__":
    main()
