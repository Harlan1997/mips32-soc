import random
import os

def generate_random_mips(filename, num_inst=100):
    alu_ops = ['add', 'addu', 'sub', 'subu', 'and', 'or', 'xor', 'nor', 'slt', 'sltu']
    alu_imm_ops = ['addi', 'addiu', 'andi', 'ori', 'xori', 'slti', 'sltiu']
    shift_ops = ['sll', 'srl', 'sra']
    shift_v_ops = ['sllv', 'srlv', 'srav']
    mult_ops = ['mult', 'multu', 'div', 'divu']
    
    # We will restrict registers to $2 - $25 to avoid messing with $0, $sp, $ra, $k0, $k1
    regs = [f'${i}' for i in range(2, 26)]
    
    with open(filename, 'w') as f:
        # Boot code at 0x0000_0000
        f.write("    .section .text.init\n")
        f.write("    .globl _start\n")
        f.write("_start:\n")
        f.write("    j main_test\n")
        f.write("    nop\n\n")
        
        # Main test code
        f.write("    .section .text\n")
        f.write("    .globl main_test\n")
        f.write("main_test:\n")
        
        # Init registers
        for r in regs:
            val = random.randint(0, 65535)
            f.write(f"    li {r}, {val}\n")
            
        f.write("\nrand_stress_loop:\n")
        
        for i in range(num_inst):
            category = random.choices(
                ['alu', 'alu_imm', 'shift', 'shift_v', 'mult', 'branch', 'mem'],
                weights=[30, 25, 10, 10, 5, 10, 10], k=1)[0]
                
            rd = random.choice(regs)
            rs = random.choice(regs)
            rt = random.choice(regs)
            
            if category == 'alu':
                op = random.choice(alu_ops)
                f.write(f"    {op} {rd}, {rs}, {rt}\n")
            elif category == 'alu_imm':
                op = random.choice(alu_imm_ops)
                imm = random.randint(-32768, 32767) if op not in ['andi', 'ori', 'xori'] else random.randint(0, 65535)
                f.write(f"    {op} {rt}, {rs}, {imm}\n")
            elif category == 'shift':
                op = random.choice(shift_ops)
                shamt = random.randint(0, 31)
                f.write(f"    {op} {rd}, {rt}, {shamt}\n")
            elif category == 'shift_v':
                op = random.choice(shift_v_ops)
                f.write(f"    {op} {rd}, {rt}, {rs}\n")
            elif category == 'mult':
                op = random.choice(mult_ops)
                f.write(f"    {op} {rs}, {rt}\n")
                if random.random() > 0.5:
                    f.write(f"    mfhi {rd}\n")
                else:
                    f.write(f"    mflo {rd}\n")
            elif category == 'branch':
                # To prevent infinite loops, we only branch forward randomly
                b_offset = random.randint(1, 5)
                b_target = f"skip_{i}"
                op = random.choice(['beq', 'bne', 'bgez', 'bgtz', 'blez', 'bltz'])
                if op in ['beq', 'bne']:
                    f.write(f"    {op} {rs}, {rt}, {b_target}\n")
                else:
                    f.write(f"    {op} {rs}, {b_target}\n")
                # Insert some padding so we jump over it
                for j in range(b_offset):
                    f.write(f"    add $0, $0, $0\n")
                f.write(f"{b_target}:\n")
            elif category == 'mem':
                # Only read from a safe RAM area to prevent bus errors
                # RAM is typically at 0x0000_0000 in this SoC
                safe_addr_base = "0x00000000"
                offset = random.randint(0, 1024) * 4
                op = random.choice(['lw', 'lh', 'lhu', 'lb', 'lbu'])
                # We need a safe pointer in a register
                f.write(f"    li $26, {safe_addr_base}\n")
                f.write(f"    {op} {rt}, {offset}($26)\n")
                
        # Finish by writing to the mailbox to stop the simulation and indicate success
        f.write("\nend_loop:\n")
        f.write("    li $26, 0xa000fffc\n")
        f.write("    li $27, 0xdeadbeef\n")
        f.write("    sw $27, 0($26)\n")
        f.write("    nop\n")
        f.write("    nop\n")
        f.write("    j end_loop\n")
        f.write("    nop\n")
        
        # Exception handler to skip faulty instructions and resume
        f.write("\n    .section .except_vector, \"ax\"\n")
        f.write("    .globl _except_handler\n")
        f.write("_except_handler:\n")
        f.write("    mfc0 $k0, $14\n")
        f.write("    mfc0 $k1, $13\n")
        f.write("    bltz $k1, is_bd\n")
        f.write("    nop\n")
        f.write("    addiu $k0, $k0, 4\n")
        f.write("    j do_eret\n")
        f.write("    nop\n")
        f.write("is_bd:\n")
        f.write("    addiu $k0, $k0, 8\n")
        f.write("do_eret:\n")
        f.write("    mtc0 $k0, $14\n")
        f.write("    eret\n")
        f.write("    nop\n")

if __name__ == "__main__":
    generate_random_mips("rand_test.s", num_inst=100)
    print("rand_test.s generated successfully with 100 instructions.")
