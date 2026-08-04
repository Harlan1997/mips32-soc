.set noreorder
.set noat
.section .text
.globl _start
_start:
  lui $t0,0x1040; mtc0 $t0,$12; nop; nop; nop
  /* Wired APB page C000_0000 -> 4000_0000. */
  mtc0 $zero,$0; nop; nop; lui $t0,0xC000; mtc0 $t0,$10; nop; nop
  lui $t0,0x0100; ori $t0,$t0,0x0017; mtc0 $t0,$2; nop; nop
  addiu $t0,$t0,0x40; mtc0 $t0,$3; nop; nop; mtc0 $zero,$5; nop; nop; tlbwi; nop; nop
  /* Wired context page C000_9000 -> 4000_9000. */
  addiu $t0,$zero,1; mtc0 $t0,$0; nop; nop; lui $t0,0xC000; ori $t0,$t0,0x9000; mtc0 $t0,$10; nop; nop
  lui $t0,0x0100; ori $t0,$t0,0x0217; mtc0 $t0,$2; nop; nop
  addiu $t0,$t0,0x40; mtc0 $t0,$3; nop; nop; mtc0 $zero,$5; nop; nop; tlbwi; nop; nop
  addiu $t0,$zero,2; mtc0 $t0,$6; nop; nop
  lui $t7,0xC000; ori $t7,$t7,0x9000; addiu $t1,$zero,1; sw $t1,20($t7)
  lw $t1,0($t7); andi $t2,$t1,0xff; addiu $t3,$zero,1; bne $t2,$t3,fail; nop
  lw $t1,12($t7); andi $t2,$t1,1; beq $t2,$zero,fail; nop; sw $t2,16($t7)
  addiu $t1,$zero,0x4001; sw $t1,4($t7); addiu $t1,$zero,1; sw $t1,8($t7); sw $t1,28($t7)
  lw $t1,36($t7); andi $t2,$t1,1; beq $t2,$zero,fail; nop
  sw $t2,32($t7); lw $t1,36($t7); andi $t2,$t1,4; beq $t2,$zero,fail; nop
  lui $t1,0x8000; ori $t1,$t1,0x0101; sw $t1,24($t7); lw $t1,12($t7); andi $t2,$t1,8; beq $t2,$zero,fail; nop
  addiu $t1,$zero,1; sw $t1,24($t7)
  lui $t0,0xA000; ori $t0,$t0,0xFFF8; lui $t1,0xC001; ori $t1,$t1,0x0004; sw $t1,0($t0)
  lui $t0,0xA000; ori $t0,$t0,0xFFFC; lui $t1,0xDEAD; ori $t1,$t1,0xBEEF; sw $t1,0($t0)
pass: b pass; nop
fail: lui $t0,0xA000; ori $t0,$t0,0xFFFC; lui $t1,0xDEAD; ori $t1,$t1,0xDEAD; sw $t1,0($t0); b fail; nop
