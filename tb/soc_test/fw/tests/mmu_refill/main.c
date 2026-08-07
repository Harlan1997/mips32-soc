/* -----------------------------------------------------------------------------
 * mmu_refill — minimal end-to-end proof that SOC_MMU_ENABLE=1 works.
 *
 * Only built/run with +define+SOC_MMU_ENABLE=1 (see run.sh in this dir). Not
 * part of the default project build -- SOC_MMU_ENABLE stays 0 for every
 * other firmware/test.
 *
 * The handler models a small software-owned page table in kseg0. On a TLB
 * miss it resolves a non-identity VA->PA mapping, installs only the faulting
 * 4KB half of the TLB pair, and ERETs to retry the access. This is a bounded
 * execution-level demand-paging slice, not a production OS page allocator.
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
static volatile unsigned int demand_fault_count = 0;
static volatile unsigned int unexpected_exc = 0;
static volatile unsigned int last_unexpected_code = 0;
static volatile unsigned int last_unexpected_badv = 0;

struct page_mapping { unsigned int va; unsigned int pa; };
static const struct page_mapping page_table[] = {
    { 0x00020000u, 0x00006000u },
    { 0x00021000u, 0x00007000u },
    { 0x00022000u, 0x00008000u },
    { 0x00023000u, 0x00009000u }
};

/* The table and backing pages are kseg0 addresses, so this path does not
 * depend on the useg mapping that caused the fault. */
static int install_page_entry(unsigned int bad_vaddr) {
    unsigned int vpn = bad_vaddr & 0xFFFFF000u;
    unsigned int pa = 0;
    unsigned int i;
    int found = 0;
    if (vpn == 0x40000000u) { pa = vpn; found = 1; }
    for (i = 0; i < sizeof(page_table) / sizeof(page_table[0]); i++) {
        if (page_table[i].va == vpn) { pa = page_table[i].pa; found = 1; break; }
    }
    if (!found) return 0;

    unsigned int vpn2 = bad_vaddr & 0xFFFFE000u;
    unsigned int leaf = ((pa >> 12) << 6) | (2u << 3) |
                        (1u << 2) | (1u << 1) | (1u << 0);
    unsigned int lo0 = ((bad_vaddr >> 12) & 1u) ? 0u : leaf;
    unsigned int lo1 = ((bad_vaddr >> 12) & 1u) ? leaf : 0u;
    unsigned int index, old_lo0, old_lo1;

    asm volatile("mtc0 %0, $10, 0" :: "r"(vpn2));   /* EntryHi: VPN2 (ASID=0) */
    asm volatile("mtc0 %0, $5,  0" :: "r"(0));       /* PageMask: 4KB (mask=0) */
    /* Reuse an existing VPN2 slot when the other half of a pair faults;
     * random replacement would leave duplicate entries and raise MCheck. */
    asm volatile("tlbp\n\t"
                 "nop\n\t nop\n\t nop\n\t nop\n\t nop\n\t"
                 "mfc0 %0, $0, 0" : "=r"(index));
    if (index & 0x80000000u) {
        asm volatile("mtc0 %0, $2, 0" :: "r"(lo0));
        asm volatile("mtc0 %0, $3, 0" :: "r"(lo1));
        asm volatile("nop\n\t nop\n\t nop\n\t nop\n\t nop");
        asm volatile("tlbwr");
    } else {
        asm volatile("tlbr\n\t nop\n\t nop\n\t nop\n\t nop\n\t nop");
        asm volatile("mfc0 %0, $2, 0" : "=r"(old_lo0));
        asm volatile("mfc0 %0, $3, 0" : "=r"(old_lo1));
        if ((bad_vaddr >> 12) & 1u) lo0 = old_lo0;
        else lo1 = old_lo1;
        asm volatile("mtc0 %0, $2, 0" :: "r"(lo0));
        asm volatile("mtc0 %0, $3, 0" :: "r"(lo1));
        asm volatile("nop\n\t nop\n\t nop\n\t nop\n\t nop");
        asm volatile("tlbwi");
    }
    refill_count++;
    if (vpn != 0x40000000u) demand_fault_count++;
    return 1;
}

void c_interrupt_handler(void) {
    unsigned int cause, exc_code, bad_vaddr, epc;
    asm volatile("mfc0 %0, $13, 0" : "=r"(cause));
    exc_code = CAUSE_EXCCODE(cause);

    if (exc_code == EXC_TLBL || exc_code == EXC_TLBS) {
        asm volatile("mfc0 %0, $8, 0" : "=r"(bad_vaddr));
        if (!install_page_entry(bad_vaddr)) {
            unexpected_exc++;
            last_unexpected_code = exc_code;
            last_unexpected_badv = bad_vaddr;
            asm volatile("mfc0 %0, $14" : "=r"(epc));
            epc += 4;
            asm volatile("mtc0 %0, $14" :: "r"(epc));
        }
        return; /* ERET retries the faulting instruction, no EPC advance */
    }

    /* Any other exception here is unexpected for this test -- record and
     * advance past it so the test can still reach its exit report instead
     * of looping forever. */
    unexpected_exc++;
    last_unexpected_code = exc_code;
    asm volatile("mfc0 %0, $8, 0" : "=r"(last_unexpected_badv));
    asm volatile("mfc0 %0, $14, 0" : "=r"(epc));
    epc += 4;
    asm volatile("mtc0 %0, $14, 0" :: "r"(epc));
}

int main(void) {
    print_str("mmu_refill: start\n");

    /* Touch four non-identity useg pages spread across the software table. */
    volatile unsigned int *p;
    unsigned int i, ok = 1;
    unsigned int bases[4] = { 0x00020000u, 0x00021000u, 0x00022000u, 0x00023000u };

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
    print_str("mmu_refill: demand_faults=");
    print_hex(demand_fault_count);
    print_str("mmu_refill: unexpected_exc=");
    print_hex(unexpected_exc);
    print_str("mmu_refill: last_code=");
    print_hex(last_unexpected_code);
    print_str("mmu_refill: last_badv=");
    print_hex(last_unexpected_badv);

    if (ok && demand_fault_count == 4 && unexpected_exc == 0) {
        print_str("mmu_refill: PASS\n");
    } else {
        print_str("mmu_refill: FAIL\n");
    }

    mailbox_exit();
    return 0;
}
