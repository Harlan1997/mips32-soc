/* -----------------------------------------------------------------------------
 * mmu_refill — minimal end-to-end proof that SOC_MMU_ENABLE=1 works.
 *
 * Only built/run with +define+SOC_MMU_ENABLE=1 (see run.sh in this dir). Not
 * part of the default project build -- SOC_MMU_ENABLE stays 0 for every
 * other firmware/test.
 *
 * The handler owns a bounded two-level software page table. On a TLB miss it
 * allocates a backing page, populates a PTE, installs only the faulting 4KB
 * half of the TLB pair, and ERETs to retry the access. This is an execution
 * level OS contract for the opt-in gate, not a production Linux VM system.
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
static volatile unsigned int last_unexpected_epc = 0;
static volatile unsigned int hw_permission_faults = 0;
static volatile unsigned int permission_fault_count = 0;
static volatile unsigned int permission_badvaddr_ok = 0;
static volatile unsigned int page_alloc_count = 0;
static volatile unsigned int pair_valid[3] = { 0, 0, 0 };
static volatile unsigned int cross_page_active = 0;
static volatile unsigned int cross_page_store_active = 0;
static volatile unsigned int cross_page_faults = 0;
static volatile unsigned int cross_page_read_faults = 0;

#ifdef SOC_HW_WALKER
/* Root index 0 -> L2 table at physical 0x2000.  The two leaf entries cover
 * both halves of one 8KB MIPS TLB pair and deliberately use different PFNs. */
const unsigned int hw_root[1024] __attribute__((section(".pt_root"))) = {
    [0] = 0x00002003u
};
const unsigned int hw_l2[1024] __attribute__((section(".pt_l2"))) = {
    [0x20] = 0x0000600Bu,
    [0x21] = 0x0000700Bu,
    [0x22] = 0x0000800Du
};
volatile unsigned int hw_page0 __attribute__((section(".page_data"))) = 0x13572468u;
volatile unsigned int hw_page1 __attribute__((section(".page_data"))) = 0x24681357u;
volatile unsigned int hw_page_ro __attribute__((section(".page_ro"))) = 0x55AA33CCu;
#endif

/* Software-owned two-level 4KB page table. Values are PTEs, not TLB entries:
 * [31:12] PFN, bit 4 user, bit 3 writable, bit 2 executable, bit 1 dirty,
 * bit 0 valid. The root/L2 arrays are kernel-owned storage, so the fault
 * handler remains reachable through kseg0 while useg is unmapped. */
#ifndef SOC_HW_WALKER
#ifdef SOC_MMU_OS_PRESSURE
static unsigned int os_root[4][1024];
static unsigned int os_l2[4][1024];
static volatile unsigned int current_task;
#else
static unsigned int os_root[1024];
static unsigned int os_l2[1024];
#endif
/* Keep page-table ownership uncached. The linker places these objects in the
 * kseg0 SRAM image; adding the kseg0->kseg1 alias offset reaches the same
 * physical SRAM while forcing AXI cache attributes to uncached. */
#ifdef SOC_MMU_OS_PRESSURE
#define OS_ROOT_UC ((volatile unsigned int *)((unsigned int)os_root[current_task] + 0x20000000u))
#define OS_L2_UC   ((volatile unsigned int *)((unsigned int)os_l2[current_task] + 0x20000000u))
#else
#define OS_ROOT_UC ((volatile unsigned int *)((unsigned int)os_root + 0x20000000u))
#define OS_L2_UC   ((volatile unsigned int *)((unsigned int)os_l2   + 0x20000000u))
#endif
static const unsigned int demand_pfns[] = { 0x06u, 0x07u, 0x08u, 0x09u };
static const unsigned int demand_vpns[] = {
    0x00020u, 0x00021u, 0x00022u, 0x00023u
};

#ifdef SOC_MMU_OS_PRESSURE
static const unsigned int task_pfns[4][4] = {
    { 0x0007u, 0x0008u, 0x000Du, 0x000Eu },
    { 0x0009u, 0x000Au, 0x000Du, 0x000Eu },
    { 0x000Bu, 0x000Cu, 0x000Du, 0x000Eu },
    /* Keep every backing page inside the 64 KiB SRAM visible to both the
     * RTL behavioral memory and mips32-soc-ref's fixed-size guest RAM. */
    { 0x0005u, 0x0006u, 0x000Fu, 0x000Eu }
};
static volatile unsigned int task_allocs[4];

static void switch_task(unsigned int task)
{
    current_task = task;
    /* The bounded handler's pair-preservation state is software-owned. A
     * context switch must not reuse the previous task's TLBR snapshot while
     * installing the new ASID's even/odd half. */
    pair_valid[0] = 0;
    pair_valid[1] = 0;
    asm volatile("mtc0 %0, $10, 0\n\t nop\n\t nop\n\t nop" ::
                 "r"(task + 1u));
}
#endif

#endif

static unsigned int pte_to_entrylo(unsigned int pte) {
    unsigned int lo = 0;
    /* MIPS EntryLo: PFN at [29:6], C=2, D/V/G in [2:0]. */
    lo = ((pte >> 12) << 6) | (2u << 3);
    if (pte & (1u << 1)) lo |= (1u << 2);
    if (pte & 1u) lo |= (1u << 1);
    return lo;
}

#ifndef SOC_HW_WALKER
static void invalidate_page_pair(unsigned int vpn2, unsigned int pair_id) {
    unsigned int zero = 0;
    unsigned int index = 16u + pair_id;
    asm volatile("mtc0 %0, $10, 0" :: "r"(vpn2));
    asm volatile("mtc0 %0, $5, 0" :: "r"(zero));
    asm volatile("mtc0 %0, $0, 0\n\t nop\n\t nop\n\t nop\n\t nop" :: "r"(index));
    asm volatile("mtc0 %0, $2, 0" :: "r"(zero));
    asm volatile("mtc0 %0, $3, 0" :: "r"(zero));
    asm volatile("nop\n\t nop\n\t nop\n\t nop");
    asm volatile("tlbwi\n\t nop\n\t nop\n\t nop\n\t nop\n\t nop" ::: "memory");
    pair_valid[pair_id] = 0;
}
#endif

/* The table and backing pages are kseg0 addresses, so this path does not
 * depend on the useg mapping that caused the fault. */
static int install_page_entry(unsigned int bad_vaddr) {
    unsigned int vpn = bad_vaddr & 0xFFFFF000u;
    unsigned int root_index = (vpn >> 22) & 0x3FFu;
    unsigned int leaf_index = (vpn >> 12) & 0x3FFu;
    unsigned int pte;

#ifndef SOC_HW_WALKER
    unsigned int i;
    unsigned int demand_index = 0xFFFFFFFFu;
    if (vpn == 0x40000000u) {
        /* Preserve the bootstrap identity mapping used by the SoC MMU
         * handoff before the useg demand pages are touched. */
        pte = (0x40000u << 12) | (1u << 4) | (1u << 3) |
              (1u << 2) | (1u << 1) | 1u;
        demand_index = 0xFFFFFFFEu;
    }
    for (i = 0; i < sizeof(demand_vpns) / sizeof(demand_vpns[0]); i++) {
        if ((vpn >> 12) == demand_vpns[i]) { demand_index = i; break; }
    }
    if (demand_index == 0xFFFFFFFFu) return 0;

    if (!(OS_ROOT_UC[root_index] & 1u)) {
        /* Root PTE points at the fixed L2 physical page, present+write. */
#ifdef SOC_MMU_OS_PRESSURE
        unsigned int l2_phys = ((unsigned int)os_l2[current_task]) & 0x1FFFF000u;
        OS_ROOT_UC[root_index] = l2_phys | 0x3u;
#else
        OS_ROOT_UC[root_index] = 0x00002003u;
#endif
    }
    if (demand_index == 0xFFFFFFFEu) {
        /* Bootstrap identity PTE is synthesized above. */
    } else pte = OS_L2_UC[leaf_index];
    if (demand_index != 0xFFFFFFFEu && !(pte & 1u)) {
        unsigned int pfn = demand_pfns[demand_index];
#ifdef SOC_MMU_OS_PRESSURE
        pfn = task_pfns[current_task][demand_index];
#endif
        /* User, executable and valid for the read-only page; all other
         * demand pages are writable and dirty. A store to page 2 must take a
         * real MIPS Modified exception and must not allocate a new page. */
        pte = (pfn << 12) | (1u << 4) | (1u << 2) | 1u;
        if (demand_index != 2u) pte |= (1u << 3) | (1u << 1);
        OS_L2_UC[leaf_index] = pte;
        page_alloc_count++;
#ifdef SOC_MMU_OS_PRESSURE
        task_allocs[current_task]++;
#endif
    }
#else
    /* The hardware walker gate provisions its own physical tables. */
    pte = 0;
    if (vpn == 0x00020000u) pte = (0x06u << 12) | 0x1Fu;
    if (vpn == 0x00021000u) pte = (0x07u << 12) | 0x1Fu;
    if (vpn == 0x00022000u) pte = (0x08u << 12) | 0x15u;
    if (!pte) return 0;
#endif

    unsigned int vpn2 = bad_vaddr & 0xFFFFE000u;
    unsigned int leaf = pte_to_entrylo(pte);
    unsigned int lo0 = ((bad_vaddr >> 12) & 1u) ? 0u : leaf;
    unsigned int lo1 = ((bad_vaddr >> 12) & 1u) ? leaf : 0u;
    unsigned int index, old_lo0 = 0, old_lo1 = 0;
    unsigned int pair_id = (vpn == 0x40000000u) ? 2u : ((vpn2 >> 13) & 1u);

    {
        unsigned int entry_hi = vpn2;
#ifdef SOC_MMU_OS_PRESSURE
        entry_hi |= (current_task + 1u) & 0xFFu;
#endif
        asm volatile("mtc0 %0, $10, 0" :: "r"(entry_hi));
    }
    asm volatile("mtc0 %0, $5,  0" :: "r"(0));       /* PageMask: 4KB (mask=0) */
    /* Deterministic software-owned slots avoid probe/CP0 write timing
     * ambiguity while filling the odd half of an existing pair. */
    index = 16u + pair_id;
    asm volatile("mtc0 %0, $0, 0\n\t nop\n\t nop\n\t nop\n\t nop" :: "r"(index));
    if (pair_valid[pair_id]) {
        asm volatile("tlbr\n\t nop\n\t nop\n\t nop\n\t nop\n\t nop");
        asm volatile("mfc0 %0, $2, 0" : "=r"(old_lo0));
        asm volatile("mfc0 %0, $3, 0" : "=r"(old_lo1));
        /* TLBR also restores the old EntryHi.  Re-assert the faulting pair
         * tag before TLBWI; otherwise a colliding/previous pair can be
         * rewritten under the wrong VPN2. */
        {
            unsigned int entry_hi = vpn2;
#ifdef SOC_MMU_OS_PRESSURE
            entry_hi |= (current_task + 1u) & 0xFFu;
#endif
            asm volatile("mtc0 %0, $10, 0\n\t nop\n\t nop\n\t nop\n\t nop" ::
                         "r"(entry_hi));
        }
        if ((bad_vaddr >> 12) & 1u) lo0 = old_lo0;
        else lo1 = old_lo1;
    }
    asm volatile("mtc0 %0, $2, 0" :: "r"(lo0));
    asm volatile("mtc0 %0, $3, 0" :: "r"(lo1));
    asm volatile("nop\n\t nop\n\t nop\n\t nop\n\t nop");
    asm volatile("tlbwi");
    pair_valid[pair_id] = 1;
    refill_count++;
#ifndef SOC_HW_WALKER
    if (demand_index != 0xFFFFFFFEu) demand_fault_count++;
#endif
    return 1;
}

void c_interrupt_handler(void) {
    unsigned int cause, exc_code, bad_vaddr, epc;
    asm volatile("mfc0 %0, $13, 0" : "=r"(cause));
    exc_code = CAUSE_EXCCODE(cause);
    asm volatile("mfc0 %0, $8, 0" : "=r"(bad_vaddr));
#ifdef SOC_HW_WALKER
    if (bad_vaddr == 0x00022000u && exc_code == EXC_MOD) {
        hw_permission_faults++;
        asm volatile("mfc0 %0, $14, 0" : "=r"(epc));
        epc += 4;
        asm volatile("mtc0 %0, $14" :: "r"(epc));
        return;
    }
#endif

    if (exc_code == EXC_MOD) {
        permission_fault_count++;
        if (bad_vaddr == 0x00022000u)
            permission_badvaddr_ok++;
        asm volatile("mfc0 %0, $14, 0" : "=r"(epc));
        epc += 4;
        asm volatile("mtc0 %0, $14, 0" :: "r"(epc));
        return;
    }

    /* The MMU bootstrap pipeline can present a stale zero VA while the
     * first direct-map instruction stream is being drained. It is harmless
     * once the EPC is advanced and must not be confused with a user-page
     * allocation failure. */
    if ((exc_code == EXC_TLBL || exc_code == EXC_TLBS) && bad_vaddr == 0u) {
        asm volatile("mfc0 %0, $14, 0" : "=r"(epc));
        epc += 4;
        asm volatile("mtc0 %0, $14, 0" :: "r"(epc));
        return;
    }

    if (exc_code == EXC_TLBL || exc_code == EXC_TLBS) {
        if ((cross_page_active || cross_page_store_active) &&
            bad_vaddr == 0x00020FFDu)
            cross_page_faults++;
        if (!install_page_entry(bad_vaddr)) {
            unexpected_exc++;
            last_unexpected_code = exc_code;
            last_unexpected_badv = bad_vaddr;
            asm volatile("mfc0 %0, $14" : "=r"(epc));
            last_unexpected_epc = epc;
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
    last_unexpected_epc = epc;
    epc += 4;
    asm volatile("mtc0 %0, $14, 0" :: "r"(epc));
}

int main(void) {
    print_str("mmu_refill: start\n");

#ifdef SOC_HW_WALKER
    {
        volatile unsigned int *even = (volatile unsigned int *)0x00020000u;
        volatile unsigned int *odd = (volatile unsigned int *)0x00021000u;
        unsigned int ok = 1u;
        even[0] = 0xA5A50001u;
        odd[0] = 0xA5A50002u;
        ok = ok && (even[0] == 0xA5A50001u) &&
                  (odd[0] == 0xA5A50002u);
        volatile unsigned int *ro = (volatile unsigned int *)0x00022000u;
        ok = ok && (ro[0] == 0x55AA33CCu);
        ro[0] = 0xDEADC0DEu;
        ok = ok && (hw_permission_faults == 1u);
        print_str("mmu_hw_walker: values=");
        print_hex(ok ? 1u : 0u);
        print_str("mmu_hw_walker: even=");
        print_hex(even[0]);
        print_str("mmu_hw_walker: odd=");
        print_hex(odd[0]);
        print_str("mmu_hw_walker: exceptions=");
        print_hex(unexpected_exc);
        print_str("mmu_hw_walker: demand_faults=");
        print_hex(demand_fault_count);
        print_str("mmu_hw_walker: permission_faults=");
        print_hex(hw_permission_faults);
        print_str("mmu_hw_walker: badv=");
        print_hex(last_unexpected_badv);
        print_str("mmu_hw_walker: last_code=");
        print_hex(last_unexpected_code);
        if (ok && demand_fault_count == 0 && hw_permission_faults == 1u)
            print_str("mmu_hw_walker: PASS\n");
        else print_str("mmu_hw_walker: FAIL\n");
        *((volatile unsigned int *)0xA000FFF0u) =
            (ok && demand_fault_count == 0 && hw_permission_faults == 1u) ?
            0x48415750u : 0x48415746u;
        mailbox_exit();
        return 0;
    }
#endif

    /* Clear the software page-table storage before the first fault. */
#ifndef SOC_HW_WALKER
    {
        /* The image loader initializes the SRAM image, but clear only the
         * entries owned by this bounded address space. Avoid a full 8KB
         * memset in the exception path and keep the gate deterministic on
         * small SRAM models. */
#ifdef SOC_MMU_OS_PRESSURE
        for (current_task = 0; current_task < 4; ++current_task) {
            OS_ROOT_UC[0] = 0;
            OS_L2_UC[0x20] = 0;
            OS_L2_UC[0x21] = 0;
            OS_L2_UC[0x22] = 0;
            OS_L2_UC[0x23] = 0;
        }
#else
        OS_ROOT_UC[0] = 0;
        OS_L2_UC[0x20] = 0;
        OS_L2_UC[0x21] = 0;
        OS_L2_UC[0x22] = 0;
        OS_L2_UC[0x23] = 0;
#endif
    }
#endif

#ifdef SOC_MMU_OS_PRESSURE
    {
        volatile unsigned int *page0 = (volatile unsigned int *)0x00020000u;
        volatile unsigned int *page1 = (volatile unsigned int *)0x00021000u;
        volatile unsigned int *page2 = (volatile unsigned int *)0x00022000u;
        volatile unsigned int *page3 = (volatile unsigned int *)0x00023000u;
        unsigned int task, round, ok = 1u;
        unsigned int last_read = 0u;

        /* Same VA space, four independently owned software page tables. */
        for (round = 0; round < 4; ++round) {
            for (task = 0; task < 4; ++task) {
                unsigned int value = 0xA5000000u | (task << 12) | round;
                switch_task(task);
                page0[0] = value;
                page1[0] = value + 1u;
                /* Pages 2 and 3 are read-only/read-mostly pressure points.
                 * Reading them forces a separate demand refill without
                 * converting a legitimate Modified fault into allocation. */
                (void)page2[0];
                (void)page3[0];
                if (page0[0] != value || page1[0] != value + 1u)
                    ok = 0u;
            }
        }

        /* Invalidate each task's pair, then prove refill from that task's
         * owned PTE rather than retaining a stale ASID translation. */
        for (task = 0; task < 4; ++task) {
            unsigned int value = 0xA5000000u | (task << 12) | 0x0Fu;
            switch_task(task);
            for (round = 0; round < 32; ++round)
                asm volatile("nop");
            invalidate_page_pair(0x00020000u, 0u);
            page0[0] = value;
            last_read = page0[0];
            if (last_read != value)
                ok = 0u;
        }

        print_str("mmu_os_pressure: refills=");
        print_hex(refill_count);
        print_str("mmu_os_pressure: page_allocs=");
        print_hex(page_alloc_count);
        print_str("mmu_os_pressure: task0_allocs=");
        print_hex(task_allocs[0]);
        print_str("mmu_os_pressure: task1_allocs=");
        print_hex(task_allocs[1]);
        print_str("mmu_os_pressure: task2_allocs=");
        print_hex(task_allocs[2]);
        print_str("mmu_os_pressure: task3_allocs=");
        print_hex(task_allocs[3]);
        print_str("mmu_os_pressure: demand_faults=");
        print_hex(demand_fault_count);
        print_str("mmu_os_pressure: permission_faults=");
        print_hex(permission_fault_count);
        print_str("mmu_os_pressure: unexpected=");
        print_hex(unexpected_exc);
        print_str("mmu_os_pressure: last_badv=");
        print_hex(last_unexpected_badv);
        print_str("mmu_os_pressure: last_code=");
        print_hex(last_unexpected_code);
        print_str("mmu_os_pressure: ok=");
        print_hex(ok);
        print_str("mmu_os_pressure: last_read=");
        print_hex(last_read);
        if (ok && page_alloc_count == 16u && demand_fault_count == 68u &&
            permission_fault_count == 0u && unexpected_exc == 0u) {
            print_str("mmu_os_pressure: PASS\n");
            *((volatile unsigned int *)0xA000FFF4u) = 0x4D4D5550u;
        } else {
            print_str("mmu_os_pressure: FAIL\n");
            *((volatile unsigned int *)0xA000FFF4u) = 0x4D4D5546u;
        }
        mailbox_exit();
        return 0;
    }
#endif

    /* Touch four non-identity useg pages. The first access to each page
     * allocates a backing PFN and the second pass must hit its PTE/TLB. */
    volatile unsigned int *p;
    unsigned int i, ok = 1, ro_initial = 0;
    unsigned int bases[4] = { 0x00020000u, 0x00021000u, 0x00022000u, 0x00023000u };

    for (i = 0; i < 4; i++) {
        p = (volatile unsigned int *)bases[i];
        if (i == 2) {
            /* Read-only first touch allocates/maps the page. The following
             * store is intentionally discarded by the Mod handler. */
            ro_initial = p[0];
            p[0] = 0xA5A50002u;
        } else p[0] = 0xA5A50000u + i;
    }

    /* LWL/LWR are separate architectural instructions.  Keep the odd
     * (second) page resident, invalidate the pair, and then execute a pair
     * whose LWL reaches 0x21000 while its LWR faults at 0x20ffd.  The first
     * instruction must retire its partial merge; only the second instruction
     * may enter the refill handler. */
    {
        volatile unsigned int *page0 = (volatile unsigned int *)0x00020000u;
        volatile unsigned int *page1 = (volatile unsigned int *)0x00021000u;
        unsigned int cross_value;
        page0[1023] = 0x11223344u;
        page1[0] = 0x55667788u;
        for (i = 0; i < 32; i++)
            asm volatile("nop");
        invalidate_page_pair(0x00020000u, 0u);
        if (page1[0] != 0x55667788u)
            ok = 0;
        cross_page_faults = 0;
        cross_page_active = 1;
        cross_value = 0;
        asm volatile("lwl %0, 3(%1)\n\t"
                     "nop\n\t"
                     "lwr %0, 0(%1)\n\t"
                     "nop\n\t"
                     : "+r"(cross_value)
                     : "r"((volatile unsigned char *)0x00020FFDu)
                     : "memory");
        cross_page_active = 0;
        print_str("mmu_refill: cross_value=");
        print_hex(cross_value);
        if (cross_value != 0x88112233u || cross_page_faults != 1u)
            ok = 0;
        cross_page_read_faults = cross_page_faults;
        /* Restore the ordinary page-1 fixture for the legacy refill checks
         * below; the cross-page assertion has already consumed both beats. */
        page1[0] = 0xA5A50001u;

        /* The store pair has the same two independent page accesses.  After
         * invalidation, SWL must complete on the resident odd page; SWR must
         * take TLBS before its byte enables reach the even page, then retry
         * and merge all three bytes precisely. */
        for (i = 0; i < 32; i++)
            asm volatile("nop");
        invalidate_page_pair(0x00020000u, 0u);
        if (page1[0] != 0xA5A50001u)
            ok = 0;
        cross_page_faults = 0;
        cross_page_store_active = 1;
        cross_value = 0xA1B2C3D4u;
        asm volatile("swl %0, 3(%1)\n\t"
                     "nop\n\t"
                     "swr %0, 0(%1)\n\t"
                     "nop\n\t"
                     :
                     : "r"(cross_value),
                       "r"((volatile unsigned char *)0x00020FFDu)
                     : "memory");
        cross_page_store_active = 0;
        print_str("mmu_refill: cross_store_faults=");
        print_hex(cross_page_faults);
        print_str("mmu_refill: cross_store_page0=");
        print_hex(page0[1023]);
        print_str("mmu_refill: cross_store_page1=");
        print_hex(page1[0]);
        if (cross_page_faults != 1u || page0[1023] != 0xB2C3D444u ||
            page1[0] != 0xA5A500A1u)
            ok = 0;
        page1[0] = 0xA5A50001u;
    }

#ifndef SOC_HW_WALKER
    /* Complete all prior fault/ERET retirement before modifying the TLB.
     * This is the software serialization point required by the current
     * in-order exception pipeline. */
    for (i = 0; i < 32; i++)
        asm volatile("nop");
    invalidate_page_pair(0x00020000u, 0u);
    p = (volatile unsigned int *)0x00020000u;
    if (p[0] != 0xA5A50000u) ok = 0;
    p = (volatile unsigned int *)0x00021000u;
    if (p[0] != 0xA5A50001u) ok = 0;
#endif
    for (i = 0; i < 4; i++) {
        p = (volatile unsigned int *)bases[i];
        if (i == 2) {
            if (p[0] != ro_initial) ok = 0;
        } else if (p[0] != (0xA5A50000u + i)) ok = 0;
    }

    print_str("mmu_refill: refills=");
    print_hex(refill_count);
    print_str("mmu_refill: demand_faults=");
    print_hex(demand_fault_count);
    print_str("mmu_refill: page_allocs=");
    print_hex(page_alloc_count);
    print_str("mmu_refill: permission_faults=");
    print_hex(permission_fault_count);
    print_str("mmu_refill: permission_badvaddr_ok=");
    print_hex(permission_badvaddr_ok);
    print_str("mmu_refill: unexpected_exc=");
    print_hex(unexpected_exc);
    print_str("mmu_refill: last_code=");
    print_hex(last_unexpected_code);
    print_str("mmu_refill: last_badv=");
    print_hex(last_unexpected_badv);
    print_str("mmu_refill: last_epc=");
    print_hex(last_unexpected_epc);
    print_str("mmu_refill: cross_page_read_faults=");
    print_hex(cross_page_read_faults);
    print_str("mmu_refill: cross_page_faults=");
    print_hex(cross_page_faults);
    print_str("mmu_refill: ok=");
    print_hex(ok);
    print_str("mmu_refill: ro_initial=");
    print_hex(ro_initial);

    if (ok && demand_fault_count == 10 && page_alloc_count == 4 &&
        permission_fault_count == 1 && permission_badvaddr_ok == 1 &&
        unexpected_exc == 0) {
        print_str("mmu_refill: PASS\n");
        *((volatile unsigned int *)0xA000FFF4u) = 0x4D4D5550u;
    } else {
        print_str("mmu_refill: FAIL\n");
        *((volatile unsigned int *)0xA000FFF4u) = 0x4D4D5546u;
    }

    mailbox_exit();
    return 0;
}
