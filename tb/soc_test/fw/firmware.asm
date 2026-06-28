
firmware.elf:     file format elf32-tradlittlemips


Disassembly of section .text.init:

00000000 <_start>:
   0:	3c081000 	lui	t0,0x1000
   4:	40886000 	mtc0	t0,c0_status
   8:	00000000 	nop
   c:	0c0000a8 	jal	2a0 <main>
  10:	3c1d0001 	lui	sp,0x1
  14:	00000000 	nop

00000018 <end_loop>:
  18:	08000006 	j	18 <end_loop>
  1c:	00000000 	nop
  20:	00000000 	nop

Disassembly of section .except:

00000180 <_except_handler>:
 180:	27bdffe0 	addiu	sp,sp,-32
 184:	afbf001c 	sw	ra,28(sp)
 188:	afa20018 	sw	v0,24(sp)
 18c:	afa30014 	sw	v1,20(sp)
 190:	afa40010 	sw	a0,16(sp)
 194:	afa5000c 	sw	a1,12(sp)
 198:	afa60008 	sw	a2,8(sp)
 19c:	0c00009a 	jal	268 <c_interrupt_handler>
 1a0:	afa70004 	sw	a3,4(sp)
 1a4:	00000000 	nop
 1a8:	8fa70004 	lw	a3,4(sp)
 1ac:	8fa60008 	lw	a2,8(sp)
 1b0:	8fa5000c 	lw	a1,12(sp)
 1b4:	8fa40010 	lw	a0,16(sp)
 1b8:	8fa30014 	lw	v1,20(sp)
 1bc:	8fa20018 	lw	v0,24(sp)
 1c0:	8fbf001c 	lw	ra,28(sp)
 1c4:	27bd0020 	addiu	sp,sp,32
 1c8:	42000018 	eret
 1cc:	00000000 	nop

Disassembly of section .text:

000001d0 <print_str>:
 1d0:	80820000 	lb	v0,0(a0)
 1d4:	10400006 	beqz	v0,1f0 <print_str+0x20>
 1d8:	3c034000 	lui	v1,0x4000
 1dc:	24840001 	addiu	a0,a0,1
 1e0:	ac620000 	sw	v0,0(v1)
 1e4:	80820000 	lb	v0,0(a0)
 1e8:	1440fffd 	bnez	v0,1e0 <print_str+0x10>
 1ec:	24840001 	addiu	a0,a0,1
 1f0:	03e00008 	jr	ra
 1f4:	00000000 	nop

000001f8 <print_hex>:
 1f8:	3c030000 	lui	v1,0x0
 1fc:	24620ad0 	addiu	v0,v1,2768
 200:	8c460004 	lw	a2,4(v0)
 204:	8c450008 	lw	a1,8(v0)
 208:	8c670ad0 	lw	a3,2768(v1)
 20c:	8c43000c 	lw	v1,12(v0)
 210:	90420010 	lbu	v0,16(v0)
 214:	27bdffe8 	addiu	sp,sp,-24
 218:	afa60004 	sw	a2,4(sp)
 21c:	afa50008 	sw	a1,8(sp)
 220:	afa3000c 	sw	v1,12(sp)
 224:	afa70000 	sw	a3,0(sp)
 228:	a3a20010 	sb	v0,16(sp)
 22c:	2403001c 	li	v1,28
 230:	3c054000 	lui	a1,0x4000
 234:	2406fffc 	li	a2,-4
 238:	00641006 	srlv	v0,a0,v1
 23c:	3042000f 	andi	v0,v0,0xf
 240:	03a21021 	addu	v0,sp,v0
 244:	80420000 	lb	v0,0(v0)
 248:	2463fffc 	addiu	v1,v1,-4
 24c:	aca20000 	sw	v0,0(a1)
 250:	1466fffa 	bne	v1,a2,23c <print_hex+0x44>
 254:	00641006 	srlv	v0,a0,v1
 258:	2402000a 	li	v0,10
 25c:	aca20000 	sw	v0,0(a1)
 260:	03e00008 	jr	ra
 264:	27bd0018 	addiu	sp,sp,24

00000268 <c_interrupt_handler>:
 268:	3c030000 	lui	v1,0x0
 26c:	8c620e50 	lw	v0,3664(v1)
 270:	3c044000 	lui	a0,0x4000
 274:	24420001 	addiu	v0,v0,1
 278:	ac620e50 	sw	v0,3664(v1)
 27c:	8c824008 	lw	v0,16392(a0)
 280:	30420004 	andi	v0,v0,0x4
 284:	10400002 	beqz	v0,290 <c_interrupt_handler+0x28>
 288:	24020001 	li	v0,1
 28c:	ac82100c 	sw	v0,4108(a0)
 290:	03e00008 	jr	ra
 294:	00000000 	nop
	...

000002a0 <main>:
 2a0:	27bdffe8 	addiu	sp,sp,-24
 2a4:	3c020000 	lui	v0,0x0
 2a8:	2403000a 	li	v1,10
 2ac:	afbf0014 	sw	ra,20(sp)
 2b0:	24420ae4 	addiu	v0,v0,2788
 2b4:	3c044000 	lui	a0,0x4000
 2b8:	24420001 	addiu	v0,v0,1
 2bc:	ac830000 	sw	v1,0(a0)
 2c0:	80430000 	lb	v1,0(v0)
 2c4:	1460fffd 	bnez	v1,2bc <main+0x1c>
 2c8:	24420001 	addiu	v0,v0,1
 2cc:	3c020000 	lui	v0,0x0
 2d0:	24030031 	li	v1,49
 2d4:	24420b0c 	addiu	v0,v0,2828
 2d8:	3c044000 	lui	a0,0x4000
 2dc:	24420001 	addiu	v0,v0,1
 2e0:	ac830000 	sw	v1,0(a0)
 2e4:	80430000 	lb	v1,0(v0)
 2e8:	1460fffd 	bnez	v1,2e0 <main+0x40>
 2ec:	24420001 	addiu	v0,v0,1
 2f0:	3c02dead 	lui	v0,0xdead
 2f4:	2403ffff 	li	v1,-1
 2f8:	3442beef 	ori	v0,v0,0xbeef
 2fc:	ac832000 	sw	v1,8192(a0)
 300:	ac822004 	sw	v0,8196(a0)
 304:	8c832004 	lw	v1,8196(a0)
 308:	10620198 	beq	v1,v0,96c <main+0x6cc>
 30c:	3c020000 	lui	v0,0x0
 310:	24030020 	li	v1,32
 314:	24420b38 	addiu	v0,v0,2872
 318:	3c044000 	lui	a0,0x4000
 31c:	24420001 	addiu	v0,v0,1
 320:	ac830000 	sw	v1,0(a0)
 324:	80430000 	lb	v1,0(v0)
 328:	1460fffd 	bnez	v1,320 <main+0x80>
 32c:	24420001 	addiu	v0,v0,1
 330:	3c020000 	lui	v0,0x0
 334:	24030032 	li	v1,50
 338:	24420b48 	addiu	v0,v0,2888
 33c:	3c044000 	lui	a0,0x4000
 340:	24420001 	addiu	v0,v0,1
 344:	ac830000 	sw	v1,0(a0)
 348:	80430000 	lb	v1,0(v0)
 34c:	1460fffd 	bnez	v1,344 <main+0xa4>
 350:	24420001 	addiu	v0,v0,1
 354:	3c021000 	lui	v0,0x1000
 358:	8c440000 	lw	a0,0(v0)
 35c:	3c020000 	lui	v0,0x0
 360:	24030020 	li	v1,32
 364:	24420b6c 	addiu	v0,v0,2924
 368:	3c054000 	lui	a1,0x4000
 36c:	24420001 	addiu	v0,v0,1
 370:	aca30000 	sw	v1,0(a1)
 374:	80430000 	lb	v1,0(v0)
 378:	1460fffd 	bnez	v1,370 <main+0xd0>
 37c:	24420001 	addiu	v0,v0,1
 380:	0c00007e 	jal	1f8 <print_hex>
 384:	00000000 	nop
 388:	3c020000 	lui	v0,0x0
 38c:	24030033 	li	v1,51
 390:	24420b88 	addiu	v0,v0,2952
 394:	3c044000 	lui	a0,0x4000
 398:	24420001 	addiu	v0,v0,1
 39c:	ac830000 	sw	v1,0(a0)
 3a0:	80430000 	lb	v1,0(v0)
 3a4:	1460fffd 	bnez	v1,39c <main+0xfc>
 3a8:	24420001 	addiu	v0,v0,1
 3ac:	3c031111 	lui	v1,0x1111
 3b0:	3c02a000 	lui	v0,0xa000
 3b4:	3442f000 	ori	v0,v0,0xf000
 3b8:	24680001 	addiu	t0,v1,1
 3bc:	24670002 	addiu	a3,v1,2
 3c0:	24660003 	addiu	a2,v1,3
 3c4:	ac430000 	sw	v1,0(v0)
 3c8:	24450100 	addiu	a1,v0,256
 3cc:	ac400100 	sw	zero,256(v0)
 3d0:	ac480004 	sw	t0,4(v0)
 3d4:	ac400104 	sw	zero,260(v0)
 3d8:	ac470008 	sw	a3,8(v0)
 3dc:	ac400108 	sw	zero,264(v0)
 3e0:	ac46000c 	sw	a2,12(v0)
 3e4:	ac40010c 	sw	zero,268(v0)
 3e8:	ac823000 	sw	v0,12288(a0)
 3ec:	24020010 	li	v0,16
 3f0:	ac853004 	sw	a1,12292(a0)
 3f4:	ac823008 	sw	v0,12296(a0)
 3f8:	24020001 	li	v0,1
 3fc:	3c034000 	lui	v1,0x4000
 400:	ac82300c 	sw	v0,12300(a0)
 404:	8c62300c 	lw	v0,12300(v1)
 408:	30420001 	andi	v0,v0,0x1
 40c:	1440fffd 	bnez	v0,404 <main+0x164>
 410:	3c02a000 	lui	v0,0xa000
 414:	3442f100 	ori	v0,v0,0xf100
 418:	8c430000 	lw	v1,0(v0)
 41c:	8c45ff00 	lw	a1,-256(v0)
 420:	8c440004 	lw	a0,4(v0)
 424:	8c42ff04 	lw	v0,-252(v0)
 428:	1082014e 	beq	a0,v0,964 <main+0x6c4>
 42c:	00651826 	xor	v1,v1,a1
 430:	00001825 	move	v1,zero
 434:	3c02a000 	lui	v0,0xa000
 438:	3442f108 	ori	v0,v0,0xf108
 43c:	8c450000 	lw	a1,0(v0)
 440:	8c44ff00 	lw	a0,-256(v0)
 444:	10a4013f 	beq	a1,a0,944 <main+0x6a4>
 448:	00000000 	nop
 44c:	8c430004 	lw	v1,4(v0)
 450:	8c42ff04 	lw	v0,-252(v0)
 454:	3c020000 	lui	v0,0x0
 458:	24030020 	li	v1,32
 45c:	24420bac 	addiu	v0,v0,2988
 460:	3c044000 	lui	a0,0x4000
 464:	24420001 	addiu	v0,v0,1
 468:	ac830000 	sw	v1,0(a0)
 46c:	80430000 	lb	v1,0(v0)
 470:	1460fffd 	bnez	v1,468 <main+0x1c8>
 474:	24420001 	addiu	v0,v0,1
 478:	3c020000 	lui	v0,0x0
 47c:	24030034 	li	v1,52
 480:	24420bbc 	addiu	v0,v0,3004
 484:	3c044000 	lui	a0,0x4000
 488:	24420001 	addiu	v0,v0,1
 48c:	ac830000 	sw	v1,0(a0)
 490:	80430000 	lb	v1,0(v0)
 494:	1460fffd 	bnez	v1,48c <main+0x1ec>
 498:	24420001 	addiu	v0,v0,1
 49c:	24020004 	li	v0,4
 4a0:	ac824004 	sw	v0,16388(a0)
 4a4:	3402ff01 	li	v0,0xff01
 4a8:	40826000 	mtc0	v0,c0_status
 4ac:	24020100 	li	v0,256
 4b0:	ac821004 	sw	v0,4100(a0)
 4b4:	24020003 	li	v0,3
 4b8:	3c030000 	lui	v1,0x0
 4bc:	ac821000 	sw	v0,4096(a0)
 4c0:	8c620e50 	lw	v0,3664(v1)
 4c4:	1040fffe 	beqz	v0,4c0 <main+0x220>
 4c8:	3c020000 	lui	v0,0x0
 4cc:	24030020 	li	v1,32
 4d0:	24420be4 	addiu	v0,v0,3044
 4d4:	3c044000 	lui	a0,0x4000
 4d8:	24420001 	addiu	v0,v0,1
 4dc:	ac830000 	sw	v1,0(a0)
 4e0:	80430000 	lb	v1,0(v0)
 4e4:	1460fffd 	bnez	v1,4dc <main+0x23c>
 4e8:	24420001 	addiu	v0,v0,1
 4ec:	3c020000 	lui	v0,0x0
 4f0:	ac801000 	sw	zero,4096(a0)
 4f4:	24030035 	li	v1,53
 4f8:	24420c0c 	addiu	v0,v0,3084
 4fc:	3c044000 	lui	a0,0x4000
 500:	24420001 	addiu	v0,v0,1
 504:	ac830000 	sw	v1,0(a0)
 508:	80430000 	lb	v1,0(v0)
 50c:	1460fffd 	bnez	v1,504 <main+0x264>
 510:	24420001 	addiu	v0,v0,1
 514:	2408000a 	li	t0,10
 518:	24090014 	li	t1,20
 51c:	01090018 	mult	t0,t1
 520:	00002010 	mfhi	a0
 524:	00001812 	mflo	v1
 528:	240200c8 	li	v0,200
 52c:	106200f9 	beq	v1,v0,914 <main+0x674>
 530:	3c020000 	lui	v0,0x0
 534:	24030020 	li	v1,32
 538:	24420c40 	addiu	v0,v0,3136
 53c:	3c044000 	lui	a0,0x4000
 540:	24420001 	addiu	v0,v0,1
 544:	ac830000 	sw	v1,0(a0)
 548:	80430000 	lb	v1,0(v0)
 54c:	1460fffd 	bnez	v1,544 <main+0x2a4>
 550:	24420001 	addiu	v0,v0,1
 554:	24080064 	li	t0,100
 558:	24090003 	li	t1,3
 55c:	15200002 	bnez	t1,568 <main+0x2c8>
 560:	0109001a 	div	zero,t0,t1
 564:	0007000d 	break	0x7
 568:	2401ffff 	li	at,-1
 56c:	15210004 	bne	t1,at,580 <main+0x2e0>
 570:	3c018000 	lui	at,0x8000
 574:	15010002 	bne	t0,at,580 <main+0x2e0>
 578:	00000000 	nop
 57c:	0006000d 	break	0x6
 580:	00004012 	mflo	t0
 584:	00005010 	mfhi	t2
 588:	00002012 	mflo	a0
 58c:	24020021 	li	v0,33
 590:	108200da 	beq	a0,v0,8fc <main+0x65c>
 594:	3c020000 	lui	v0,0x0
 598:	24030020 	li	v1,32
 59c:	24420c5c 	addiu	v0,v0,3164
 5a0:	3c054000 	lui	a1,0x4000
 5a4:	24420001 	addiu	v0,v0,1
 5a8:	aca30000 	sw	v1,0(a1)
 5ac:	80430000 	lb	v1,0(v0)
 5b0:	1460fffd 	bnez	v1,5a8 <main+0x308>
 5b4:	24420001 	addiu	v0,v0,1
 5b8:	0c00007e 	jal	1f8 <print_hex>
 5bc:	00000000 	nop
 5c0:	3c020000 	lui	v0,0x0
 5c4:	24030020 	li	v1,32
 5c8:	24420c70 	addiu	v0,v0,3184
 5cc:	3c044000 	lui	a0,0x4000
 5d0:	24420001 	addiu	v0,v0,1
 5d4:	ac830000 	sw	v1,0(a0)
 5d8:	80430000 	lb	v1,0(v0)
 5dc:	1460fffd 	bnez	v1,5d4 <main+0x334>
 5e0:	24420001 	addiu	v0,v0,1
 5e4:	0c00007e 	jal	1f8 <print_hex>
 5e8:	01402025 	move	a0,t2
 5ec:	3c081234 	lui	t0,0x1234
 5f0:	35085678 	ori	t0,t0,0x5678
 5f4:	3c099abc 	lui	t1,0x9abc
 5f8:	3529def0 	ori	t1,t1,0xdef0
 5fc:	01000011 	mthi	t0
 600:	01200013 	mtlo	t1
 604:	00001810 	mfhi	v1
 608:	00002012 	mflo	a0
 60c:	3c021234 	lui	v0,0x1234
 610:	24425678 	addiu	v0,v0,22136
 614:	106200b2 	beq	v1,v0,8e0 <main+0x640>
 618:	3c020000 	lui	v0,0x0
 61c:	24030020 	li	v1,32
 620:	24420c98 	addiu	v0,v0,3224
 624:	3c044000 	lui	a0,0x4000
 628:	24420001 	addiu	v0,v0,1
 62c:	ac830000 	sw	v1,0(a0)
 630:	80430000 	lb	v1,0(v0)
 634:	1460fffd 	bnez	v1,62c <main+0x38c>
 638:	24420001 	addiu	v0,v0,1
 63c:	3c020000 	lui	v0,0x0
 640:	24030036 	li	v1,54
 644:	24420cac 	addiu	v0,v0,3244
 648:	3c044000 	lui	a0,0x4000
 64c:	24420001 	addiu	v0,v0,1
 650:	ac830000 	sw	v1,0(a0)
 654:	80430000 	lb	v1,0(v0)
 658:	1460fffd 	bnez	v1,650 <main+0x3b0>
 65c:	24420001 	addiu	v0,v0,1
 660:	240800ff 	li	t0,255
 664:	24090008 	li	t1,8
 668:	01281804 	sllv	v1,t0,t1
 66c:	01002027 	nor	a0,t0,zero
 670:	0109282b 	sltu	a1,t0,t1
 674:	3402ff00 	li	v0,0xff00
 678:	1062008c 	beq	v1,v0,8ac <main+0x60c>
 67c:	2402ff00 	li	v0,-256
 680:	3c020000 	lui	v0,0x0
 684:	24030020 	li	v1,32
 688:	24420cdc 	addiu	v0,v0,3292
 68c:	3c044000 	lui	a0,0x4000
 690:	24420001 	addiu	v0,v0,1
 694:	ac830000 	sw	v1,0(a0)
 698:	80430000 	lb	v1,0(v0)
 69c:	1460fffd 	bnez	v1,694 <main+0x3f4>
 6a0:	24420001 	addiu	v0,v0,1
 6a4:	3c020000 	lui	v0,0x0
 6a8:	24030037 	li	v1,55
 6ac:	24420cec 	addiu	v0,v0,3308
 6b0:	3c044000 	lui	a0,0x4000
 6b4:	24420001 	addiu	v0,v0,1
 6b8:	ac830000 	sw	v1,0(a0)
 6bc:	80430000 	lb	v1,0(v0)
 6c0:	1460fffd 	bnez	v1,6b8 <main+0x418>
 6c4:	24420001 	addiu	v0,v0,1
 6c8:	2408ffff 	li	t0,-1
 6cc:	05100002 	bltzal	t0,6d8 <main+0x438>
 6d0:	00000000 	nop
 6d4:	00000000 	nop
 6d8:	03e01025 	move	v0,ra
 6dc:	24080001 	li	t0,1
 6e0:	05110002 	bgezal	t0,6ec <main+0x44c>
 6e4:	00000000 	nop
 6e8:	00000000 	nop
 6ec:	03e01825 	move	v1,ra
 6f0:	10400064 	beqz	v0,884 <main+0x5e4>
 6f4:	3c020000 	lui	v0,0x0
 6f8:	10600063 	beqz	v1,888 <main+0x5e8>
 6fc:	24030020 	li	v1,32
 700:	3c020000 	lui	v0,0x0
 704:	24420d18 	addiu	v0,v0,3352
 708:	3c044000 	lui	a0,0x4000
 70c:	24420001 	addiu	v0,v0,1
 710:	ac830000 	sw	v1,0(a0)
 714:	80430000 	lb	v1,0(v0)
 718:	1460fffd 	bnez	v1,710 <main+0x470>
 71c:	24420001 	addiu	v0,v0,1
 720:	3c020000 	lui	v0,0x0
 724:	24030038 	li	v1,56
 728:	24420d44 	addiu	v0,v0,3396
 72c:	3c044000 	lui	a0,0x4000
 730:	24420001 	addiu	v0,v0,1
 734:	ac830000 	sw	v1,0(a0)
 738:	80430000 	lb	v1,0(v0)
 73c:	1460fffd 	bnez	v1,734 <main+0x494>
 740:	24420001 	addiu	v0,v0,1
 744:	3c02aaaa 	lui	v0,0xaaaa
 748:	3c03bbbb 	lui	v1,0xbbbb
 74c:	3c04cccc 	lui	a0,0xcccc
 750:	3442aaaa 	ori	v0,v0,0xaaaa
 754:	3463bbbb 	ori	v1,v1,0xbbbb
 758:	3484cccc 	ori	a0,a0,0xcccc
 75c:	ac022000 	sw	v0,8192(zero)
 760:	ac033000 	sw	v1,12288(zero)
 764:	ac044000 	sw	a0,16384(zero)
 768:	8c052000 	lw	a1,8192(zero)
 76c:	10a200a6 	beq	a1,v0,a08 <main+0x768>
 770:	00000000 	nop
 774:	3c020000 	lui	v0,0x0
 778:	24030020 	li	v1,32
 77c:	24420d7c 	addiu	v0,v0,3452
 780:	3c044000 	lui	a0,0x4000
 784:	24420001 	addiu	v0,v0,1
 788:	ac830000 	sw	v1,0(a0)
 78c:	80430000 	lb	v1,0(v0)
 790:	1460fffd 	bnez	v1,788 <main+0x4e8>
 794:	24420001 	addiu	v0,v0,1
 798:	3c020000 	lui	v0,0x0
 79c:	24030039 	li	v1,57
 7a0:	24420d98 	addiu	v0,v0,3480
 7a4:	3c044000 	lui	a0,0x4000
 7a8:	24420001 	addiu	v0,v0,1
 7ac:	ac830000 	sw	v1,0(a0)
 7b0:	80430000 	lb	v1,0(v0)
 7b4:	1460fffd 	bnez	v1,7ac <main+0x50c>
 7b8:	24420001 	addiu	v0,v0,1
 7bc:	3c0389ab 	lui	v1,0x89ab
 7c0:	3463cdef 	ori	v1,v1,0xcdef
 7c4:	24025000 	li	v0,20480
 7c8:	ac035000 	sw	v1,20480(zero)
 7cc:	80420000 	lb	v0,0(v0)
 7d0:	90440001 	lbu	a0,1(v0)
 7d4:	84460000 	lh	a2,0(v0)
 7d8:	94450002 	lhu	a1,2(v0)
 7dc:	2403ffef 	li	v1,-17
 7e0:	10430078 	beq	v0,v1,9c4 <main+0x724>
 7e4:	240200cd 	li	v0,205
 7e8:	3c020000 	lui	v0,0x0
 7ec:	24030020 	li	v1,32
 7f0:	24420dd8 	addiu	v0,v0,3544
 7f4:	3c044000 	lui	a0,0x4000
 7f8:	24420001 	addiu	v0,v0,1
 7fc:	ac830000 	sw	v1,0(a0)
 800:	80430000 	lb	v1,0(v0)
 804:	1460fffd 	bnez	v1,7fc <main+0x55c>
 808:	24420001 	addiu	v0,v0,1
 80c:	ac005004 	sw	zero,20484(zero)
 810:	24045004 	li	a0,20484
 814:	24020012 	li	v0,18
 818:	24033456 	li	v1,13398
 81c:	a0820000 	sb	v0,0(a0)
 820:	a4830002 	sh	v1,2(a0)
 824:	3c023456 	lui	v0,0x3456
 828:	8c035004 	lw	v1,20484(zero)
 82c:	24420012 	addiu	v0,v0,18
 830:	10620059 	beq	v1,v0,998 <main+0x6f8>
 834:	3c020000 	lui	v0,0x0
 838:	24030020 	li	v1,32
 83c:	24420e08 	addiu	v0,v0,3592
 840:	3c044000 	lui	a0,0x4000
 844:	24420001 	addiu	v0,v0,1
 848:	ac830000 	sw	v1,0(a0)
 84c:	80430000 	lb	v1,0(v0)
 850:	1460fffd 	bnez	v1,848 <main+0x5a8>
 854:	24420001 	addiu	v0,v0,1
 858:	3c020000 	lui	v0,0x0
 85c:	2403002d 	li	v1,45
 860:	24420e24 	addiu	v0,v0,3620
 864:	3c044000 	lui	a0,0x4000
 868:	24420001 	addiu	v0,v0,1
 86c:	ac830000 	sw	v1,0(a0)
 870:	80430000 	lb	v1,0(v0)
 874:	1460fffc 	bnez	v1,868 <main+0x5c8>
 878:	00000000 	nop
 87c:	1000ffff 	b	87c <main+0x5dc>
 880:	00000000 	nop
 884:	24030020 	li	v1,32
 888:	24420d2c 	addiu	v0,v0,3372
 88c:	3c044000 	lui	a0,0x4000
 890:	24420001 	addiu	v0,v0,1
 894:	ac830000 	sw	v1,0(a0)
 898:	80430000 	lb	v1,0(v0)
 89c:	1460fffc 	bnez	v1,890 <main+0x5f0>
 8a0:	00000000 	nop
 8a4:	1000ff9f 	b	724 <main+0x484>
 8a8:	3c020000 	lui	v0,0x0
 8ac:	1482ff74 	bne	a0,v0,680 <main+0x3e0>
 8b0:	00000000 	nop
 8b4:	14a0ff72 	bnez	a1,680 <main+0x3e0>
 8b8:	3c020000 	lui	v0,0x0
 8bc:	24420cd0 	addiu	v0,v0,3280
 8c0:	10000002 	b	8cc <main+0x62c>
 8c4:	3c044000 	lui	a0,0x4000
 8c8:	ac830000 	sw	v1,0(a0)
 8cc:	80430000 	lb	v1,0(v0)
 8d0:	1460fffd 	bnez	v1,8c8 <main+0x628>
 8d4:	24420001 	addiu	v0,v0,1
 8d8:	1000ff73 	b	6a8 <main+0x408>
 8dc:	3c020000 	lui	v0,0x0
 8e0:	3c029abc 	lui	v0,0x9abc
 8e4:	3442def0 	ori	v0,v0,0xdef0
 8e8:	1082006f 	beq	a0,v0,aa8 <main+0x808>
 8ec:	24030020 	li	v1,32
 8f0:	3c020000 	lui	v0,0x0
 8f4:	1000ff4b 	b	624 <main+0x384>
 8f8:	24420c98 	addiu	v0,v0,3224
 8fc:	24020001 	li	v0,1
 900:	1142005f 	beq	t2,v0,a80 <main+0x7e0>
 904:	24030020 	li	v1,32
 908:	3c020000 	lui	v0,0x0
 90c:	1000ff24 	b	5a0 <main+0x300>
 910:	24420c5c 	addiu	v0,v0,3164
 914:	1480004b 	bnez	a0,a44 <main+0x7a4>
 918:	24030020 	li	v1,32
 91c:	3c020000 	lui	v0,0x0
 920:	24420c34 	addiu	v0,v0,3124
 924:	3c044000 	lui	a0,0x4000
 928:	24420001 	addiu	v0,v0,1
 92c:	ac830000 	sw	v1,0(a0)
 930:	80430000 	lb	v1,0(v0)
 934:	1460fffd 	bnez	v1,92c <main+0x68c>
 938:	24420001 	addiu	v0,v0,1
 93c:	1000ff05 	b	554 <main+0x2b4>
 940:	00000000 	nop
 944:	8c440004 	lw	a0,4(v0)
 948:	8c42ff04 	lw	v0,-252(v0)
 94c:	10820040 	beq	a0,v0,a50 <main+0x7b0>
 950:	00000000 	nop
 954:	3c020000 	lui	v0,0x0
 958:	24030020 	li	v1,32
 95c:	1000fec0 	b	460 <main+0x1c0>
 960:	24420bac 	addiu	v0,v0,2988
 964:	1000feb3 	b	434 <main+0x194>
 968:	2c630001 	sltiu	v1,v1,1
 96c:	3c020000 	lui	v0,0x0
 970:	24030020 	li	v1,32
 974:	24420b20 	addiu	v0,v0,2848
 978:	3c044000 	lui	a0,0x4000
 97c:	24420001 	addiu	v0,v0,1
 980:	ac830000 	sw	v1,0(a0)
 984:	80430000 	lb	v1,0(v0)
 988:	1460fffc 	bnez	v1,97c <main+0x6dc>
 98c:	00000000 	nop
 990:	1000fe68 	b	334 <main+0x94>
 994:	3c020000 	lui	v0,0x0
 998:	3c020000 	lui	v0,0x0
 99c:	24030020 	li	v1,32
 9a0:	24420df0 	addiu	v0,v0,3568
 9a4:	3c044000 	lui	a0,0x4000
 9a8:	24420001 	addiu	v0,v0,1
 9ac:	ac830000 	sw	v1,0(a0)
 9b0:	80430000 	lb	v1,0(v0)
 9b4:	1460fffc 	bnez	v1,9a8 <main+0x708>
 9b8:	00000000 	nop
 9bc:	1000ffa7 	b	85c <main+0x5bc>
 9c0:	3c020000 	lui	v0,0x0
 9c4:	1482ff89 	bne	a0,v0,7ec <main+0x54c>
 9c8:	3c020000 	lui	v0,0x0
 9cc:	2402cdef 	li	v0,-12817
 9d0:	14c2ff86 	bne	a2,v0,7ec <main+0x54c>
 9d4:	3c020000 	lui	v0,0x0
 9d8:	340289ab 	li	v0,0x89ab
 9dc:	14a2ff82 	bne	a1,v0,7e8 <main+0x548>
 9e0:	3c020000 	lui	v0,0x0
 9e4:	24420dc0 	addiu	v0,v0,3520
 9e8:	10000002 	b	9f4 <main+0x754>
 9ec:	3c044000 	lui	a0,0x4000
 9f0:	ac830000 	sw	v1,0(a0)
 9f4:	80430000 	lb	v1,0(v0)
 9f8:	1460fffd 	bnez	v1,9f0 <main+0x750>
 9fc:	24420001 	addiu	v0,v0,1
 a00:	1000ff82 	b	80c <main+0x56c>
 a04:	00000000 	nop
 a08:	8c023000 	lw	v0,12288(zero)
 a0c:	1443ff5a 	bne	v0,v1,778 <main+0x4d8>
 a10:	3c020000 	lui	v0,0x0
 a14:	8c024000 	lw	v0,16384(zero)
 a18:	1444ff56 	bne	v0,a0,774 <main+0x4d4>
 a1c:	3c020000 	lui	v0,0x0
 a20:	24420d64 	addiu	v0,v0,3428
 a24:	10000002 	b	a30 <main+0x790>
 a28:	3c044000 	lui	a0,0x4000
 a2c:	ac830000 	sw	v1,0(a0)
 a30:	80430000 	lb	v1,0(v0)
 a34:	1460fffd 	bnez	v1,a2c <main+0x78c>
 a38:	24420001 	addiu	v0,v0,1
 a3c:	1000ff57 	b	79c <main+0x4fc>
 a40:	3c020000 	lui	v0,0x0
 a44:	3c020000 	lui	v0,0x0
 a48:	1000febc 	b	53c <main+0x29c>
 a4c:	24420c40 	addiu	v0,v0,3136
 a50:	1060ffc0 	beqz	v1,954 <main+0x6b4>
 a54:	3c044000 	lui	a0,0x4000
 a58:	3c020000 	lui	v0,0x0
 a5c:	24030020 	li	v1,32
 a60:	24420b9c 	addiu	v0,v0,2972
 a64:	24420001 	addiu	v0,v0,1
 a68:	ac830000 	sw	v1,0(a0)
 a6c:	80430000 	lb	v1,0(v0)
 a70:	1460fffc 	bnez	v1,a64 <main+0x7c4>
 a74:	00000000 	nop
 a78:	1000fe80 	b	47c <main+0x1dc>
 a7c:	3c020000 	lui	v0,0x0
 a80:	3c020000 	lui	v0,0x0
 a84:	24420c50 	addiu	v0,v0,3152
 a88:	3c044000 	lui	a0,0x4000
 a8c:	24420001 	addiu	v0,v0,1
 a90:	ac830000 	sw	v1,0(a0)
 a94:	80430000 	lb	v1,0(v0)
 a98:	1460fffd 	bnez	v1,a90 <main+0x7f0>
 a9c:	24420001 	addiu	v0,v0,1
 aa0:	1000fed2 	b	5ec <main+0x34c>
 aa4:	00000000 	nop
 aa8:	3c020000 	lui	v0,0x0
 aac:	24420c84 	addiu	v0,v0,3204
 ab0:	3c044000 	lui	a0,0x4000
 ab4:	24420001 	addiu	v0,v0,1
 ab8:	ac830000 	sw	v1,0(a0)
 abc:	80430000 	lb	v1,0(v0)
 ac0:	1460fffc 	bnez	v1,ab4 <main+0x814>
 ac4:	00000000 	nop
 ac8:	1000fedd 	b	640 <main+0x3a0>
 acc:	3c020000 	lui	v0,0x0
