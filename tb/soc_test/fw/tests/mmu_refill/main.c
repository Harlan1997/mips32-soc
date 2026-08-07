/* -----------------------------------------------------------------------------
 * mmu_refill — minimal end-to-end proof that SOC_MMU_ENABLE=1 works.
 *
 * Only built/run with +define+SOC_MMU_ENABLE=1 (see run.sh in this dir). Not
 * part of the default project build -- SOC_MMU_ENABLE stays 0 for every
 * other firmware/test.
 *
 * This does NOT implement real demand paging. On any TLB miss (TLBL/TLBS),
 * the exception handler installs a single identity-mapped 4KB entry for the
 * faulting page (PA == VA, uncached C=3'b010, valid,
 * dirty, global) via TLBWR, then ERETs to retry the faulting instruction.
 * This is enough to prove the CP0/TLB/mips_mmu translation path actually
 * works under real firmware, without taking on page-table-based paging.
 * -------------------------------------------------------------------------- */
#include "soc_addr.h"
#include "print.h"

/* CP0 register numbers used here (MIPS32r2, sel=0 unless noted):
 *   $8  BadVAddr   $10 EntryHi   $2  EntryLo0   $13 Cause   $14 EPC
 */

#define CAUSE_EXCCODE(c)   (((c) >> 2) & 0x1F)
#define EXC_MOD   1
#define EXC_TLBL  2
#define EXC_TLBS  3
#define EXC_ADEL  4
#define EXC_ADES  5

static volatile unsigned int refill_count = 0;
static volatile unsigned int unexpected_exc = 0;

/* Install an identity mapping for the 4KB page containing bad_vaddr and
 * retry. EntryLo0/1 cover the even/odd 4KB halves of the 8KB TLB pair so
 * identity mapping preserves the page offset across VA[12]. */
static void install_identity_entry(unsigned int bad_vaddr) {
    unsigned int vpn2  = bad_vaddr & 0xFFFFE000u;   /* VA[31:13], EntryHi field */
    unsigned int pfn   = (bad_vaddr >> 12) & 0xFFFFFu; /* identity: PFN = VA>>12 */
    unsigned int lo0    = (pfn << 6) | (2u << 3) /* C=uncached */
                         | (1u << 2) /* D */ | (1u << 1) /* V */ | (1u << 0); /* G */
    unsigned int lo1    = ((pfn + 1u) << 6) | (2u << 3)
                         | (1u << 2) | (1u << 1) | (1u << 0);

    asm volatile("mtc0 %0, $10, 0" :: "r"(vpn2));   /* EntryHi: VPN2 (ASID=0) */
    asm volatile("mtc0 %0, $2,  0" :: "r"(lo0));     /* EntryLo0 */
    asm volatile("mtc0 %0, $3,  0" :: "r"(lo1));     /* EntryLo1 */
    asm volatile("mtc0 %0, $5,  0" :: "r"(0));       /* PageMask: 4KB (mask=0) */
    asm volatile("tlbwr");
    refill_count++;
}

void c_interrupt_handler(void) {
    unsigned int cause, exc_code, bad_vaddr, epc;
    asm volatile("mfc0 %0, $13, 0" : "=r"(cause));
    exc_code = CAUSE_EXCCODE(cause);

    if (exc_code == EXC_TLBL || exc_code == EXC_TLBS) {
        asm volatile("mfc0 %0, $8, 0" : "=r"(bad_vaddr));
        install_identity_entry(bad_vaddr);
        return; /* ERET retries the faulting instruction, no EPC advance */
    }

    /* Any other exception here is unexpected for this test -- record and
     * advance past it so the test can still reach its exit report instead
     * of looping forever. */
    unexpected_exc++;
    asm volatile("mfc0 %0, $14, 0" : "=r"(epc));
    epc += 4;
    asm volatile("mtc0 %0, $14, 0" :: "r"(epc));
}

int main(void) {
    print_str("mmu_refill: start\n");

    /* Touch a handful of useg words spread across several 4KB pages so we
     * exercise multiple TLB misses/refills, not just one lucky entry. */
    volatile unsigned int *p;
    unsigned int i, ok = 1;
    /* Use four useg pages in the backed SRAM window. The product DDR refill
     * path has its own gate; keeping this bootstrap gate on SRAM isolates the
     * reset/vector/TLB/ERET contract from DDR controller behavior. */
    unsigned int bases[4] = { 0x00006000u, 0x00007000u, 0x00008000u, 0x00009000u };

    for (i = 0; i < 4; i++) {
        p = (volatile unsigned int *)bases[i];
        p[0] = 0xA5A50000u + i;
    }
    for (i = 0; i < 4; i++) {
        p = (volatile unsigned int *)bases[i];
        if (p[0] != (0xA5A50000u + i)) ok = 0;
    }

    print_str("mmu_refill: refills=");
    print_hex(refill_count);
    print_str("mmu_refill: unexpected_exc=");
    print_hex(unexpected_exc);

    if (ok && refill_count > 0 && unexpected_exc == 0) {
        print_str("mmu_refill: PASS\n");
    } else {
        print_str("mmu_refill: FAIL\n");
    }

    mailbox_exit();
    return 0;
}
