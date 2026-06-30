    .section .text.init
    .globl _start
_start:
    j main_test
    nop

    .section .text
    .globl main_test
main_test:
    li $2, 15002
    li $3, 10878
    li $4, 39329
    li $5, 24566
    li $6, 16287
    li $7, 16201
    li $8, 42092
    li $9, 5215
    li $10, 10546
    li $11, 39945
    li $12, 17160
    li $13, 44827
    li $14, 5799
    li $15, 11554
    li $16, 9583
    li $17, 52849
    li $18, 42868
    li $19, 7248
    li $20, 28659
    li $21, 8132
    li $22, 34366
    li $23, 23779
    li $24, 50153
    li $25, 27432

rand_stress_loop:
    add $25, $6, $10
    slti $18, $12, -3181
    ori $18, $25, 44310
    xori $21, $13, 8970
    or $3, $18, $15
    beq $4, $9, skip_5
    add $0, $0, $0
    add $0, $0, $0
    add $0, $0, $0
    add $0, $0, $0
skip_5:
    addi $24, $22, -1975
    sra $18, $16, 0
    sra $15, $4, 7
    blez $10, skip_9
    add $0, $0, $0
    add $0, $0, $0
    add $0, $0, $0
    add $0, $0, $0
skip_9:
    or $23, $6, $24
    li $26, 0x00000000
    lh $13, 72($26)
    li $26, 0x00000000
    lhu $19, 1856($26)
    and $23, $3, $19
    srav $12, $21, $11
    addi $2, $2, -21358
    srlv $3, $20, $23
    andi $15, $4, 58507
    sltiu $10, $23, -27906
    subu $24, $8, $6
    srlv $5, $6, $7
    li $26, 0x00000000
    lhu $24, 1972($26)
    xor $13, $11, $3
    xor $3, $6, $6
    subu $2, $6, $20
    sll $14, $10, 12
    multu $2, $18
    mflo $9
    srav $19, $16, $18
    bltz $12, skip_28
    add $0, $0, $0
    add $0, $0, $0
    add $0, $0, $0
    add $0, $0, $0
    add $0, $0, $0
skip_28:
    sllv $17, $10, $9
    xor $11, $16, $24
    bgez $18, skip_31
    add $0, $0, $0
skip_31:
    and $8, $22, $11
    li $26, 0x00000000
    lhu $18, 212($26)
    slti $13, $8, -4107
    srl $4, $18, 13
    add $23, $23, $13
    addu $22, $4, $4
    slti $17, $3, 25905
    sltu $12, $10, $11
    xor $15, $23, $13
    divu $20, $24
    mfhi $5
    sll $3, $21, 17
    mult $17, $25
    mflo $8
    bltz $11, skip_44
    add $0, $0, $0
    add $0, $0, $0
    add $0, $0, $0
    add $0, $0, $0
    add $0, $0, $0
skip_44:
    li $26, 0x00000000
    lb $14, 3456($26)
    xori $12, $4, 47020
    sltiu $5, $12, -32727
    addiu $23, $19, -17256
    li $26, 0x00000000
    lbu $16, 500($26)
    sub $16, $2, $10
    sll $18, $25, 1
    srav $7, $18, $14
    multu $5, $11
    mflo $23
    addi $10, $19, 31276
    nor $18, $9, $6
    li $26, 0x00000000
    lh $22, 656($26)
    sltu $11, $3, $16
    blez $16, skip_58
    add $0, $0, $0
    add $0, $0, $0
    add $0, $0, $0
    add $0, $0, $0
    add $0, $0, $0
skip_58:
    addu $7, $19, $5
    li $26, 0x00000000
    lb $7, 2404($26)
    srav $25, $16, $25
    mult $8, $8
    mflo $6
    xor $16, $6, $11
    or $11, $10, $5
    srav $18, $13, $4
    sll $18, $9, 29
    bgez $5, skip_67
    add $0, $0, $0
    add $0, $0, $0
    add $0, $0, $0
    add $0, $0, $0
    add $0, $0, $0
skip_67:
    add $21, $21, $17
    slti $18, $12, -4203
    li $26, 0x00000000
    lb $22, 2252($26)
    li $26, 0x00000000
    lh $2, 952($26)
    sltiu $10, $23, 28984
    srlv $25, $4, $6
    sltu $2, $13, $2
    mult $19, $20
    mflo $12
    srav $15, $16, $3
    beq $7, $18, skip_77
    add $0, $0, $0
    add $0, $0, $0
skip_77:
    nor $25, $15, $10
    bgtz $11, skip_79
    add $0, $0, $0
    add $0, $0, $0
    add $0, $0, $0
    add $0, $0, $0
    add $0, $0, $0
skip_79:
    sltiu $3, $18, -11032
    sllv $23, $15, $24
    xori $19, $6, 32948
    xor $18, $15, $20
    srl $10, $5, 19
    srav $13, $24, $14
    addi $21, $3, 27076
    div $9, $20
    mfhi $14
    li $26, 0x00000000
    lb $4, 3584($26)
    divu $14, $6
    mflo $3
    slt $14, $5, $25
    srlv $20, $13, $19
    sllv $22, $16, $11
    sll $10, $12, 15
    sra $24, $23, 23
    nor $11, $13, $21
    blez $18, skip_96
    add $0, $0, $0
    add $0, $0, $0
    add $0, $0, $0
    add $0, $0, $0
skip_96:
    bgtz $6, skip_97
    add $0, $0, $0
skip_97:
    addi $19, $7, -23170
    srav $21, $17, $23

end_loop:
    li $26, 0xa000fffc
    li $27, 0xdeadbeef
    sw $27, 0($26)
    nop
    nop
    j end_loop
    nop

    .section .except_vector, "ax"
    .globl _except_handler
_except_handler:
    mfc0 $k0, $14
    mfc0 $k1, $13
    bltz $k1, is_bd
    nop
    addiu $k0, $k0, 4
    j do_eret
    nop
is_bd:
    addiu $k0, $k0, 8
do_eret:
    mtc0 $k0, $14
    eret
    nop
