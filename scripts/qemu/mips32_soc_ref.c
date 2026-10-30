/*
 * Minimal MIPS32 SoC reference machine for RTL differential testing.
 *
 * This machine intentionally models only the prototype contract needed to
 * boot the project's bare-metal ELF images. It is not a product platform.
 */

#include "qemu/osdep.h"
#include "qemu/units.h"
#include "exec/address-spaces.h"
#include "exec/exec-all.h"
#include "exec/memory.h"
#include "hw/boards.h"
#include "hw/irq.h"
#include "hw/loader.h"
#include "hw/mips/mips.h"
#include "qapi/error.h"
#include "qemu/error-report.h"
#include "qemu/main-loop.h"
#include "qemu/timer.h"
#include "exec/cpu-common.h"
#include "sysemu/runstate.h"
#include "sysemu/reset.h"
#include "target/mips/internal.h"
#include "target/mips/tcg/tcg-internal.h"
#include "cpu.h"
#include "elf.h"
#include "mips32_soc_uart_timing.h"

static bool soc_ref_linux_guest;
static bool soc_ref_rtl_cp0_identity;

/* The RTL CP0 contract exposes LLAddr as the aligned virtual address. */
bool qemu_mips32_soc_ref_lladdr_virtual(void)
{
    return true;
}

/* Linux keeps a reservation after a failed SC, while a successful SC consumes
 * it.  Bare-metal RTL differential keeps the stricter SoC contract in which
 * every completed SC attempt consumes the reservation. */
bool qemu_mips32_soc_ref_sc_consume_reservation(void)
{
    return !soc_ref_linux_guest;
}

#define SOC_SRAM_SIZE      (64 * KiB)
#define SOC_BOOTROM_BASE   0x1fc00000ULL
#define SOC_BOOTROM_SIZE   (64 * KiB)
#define SOC_SRAM_ALIAS     0xa0000000ULL
#define SOC_UART_BASE      0x40000000ULL
#define SOC_UART_APB_BASE  0x04000000U
#define SOC_UART_SIZE      0x1000
#define SOC_MAILBOX_BASE   0xa000fffcULL
#define SOC_MAILBOX_MAGIC  0xdeadbeefU
#define SOC_REF_IRQ_PC_HISTORY_SIZE 8U
#define SOC_REF_IRQ_EARLY_RELEASE_MAX_TICKS 1U
#define SOC_REF_LINUX_TERMINAL_MARKER "MIPS32_SOC_LINUX_TERMINAL\n"
#define SOC_DDR_BASE       0x08000000ULL
#define SOC_DDR_SIZE       (128 * MiB)
#define SOC_LINUX_RNG_ENV_BASE 0x09d00000ULL
#define SOC_LINUX_FDT_BASE 0x09f00000ULL
#define SOC_FLASH_BASE     0x10000000ULL
#define SOC_FLASH_SIZE     (256 * MiB)
#define SOC_APB_BASE       0x40000000ULL
#define SOC_APB_SIZE       0x10000
#define SOC_FDT_MAX_SIZE   (64 * KiB)

typedef struct MIPS32SocRefState {
    MemoryRegion bootrom;
    MemoryRegion mailbox;
    MemoryRegion *sram;
    MemoryRegion uart;
    MemoryRegion malta_uart;
    MemoryRegion dma_legacy;
    MemoryRegion dma_v2_window;
    MemoryRegion pic_window;
    MemoryRegion qspi_window;
    MemoryRegion ddr_status_window;
    MemoryRegion ipi_window[2];
    MemoryRegion uart_mmu_alias;
    MemoryRegion uart_mmu_odd_alias;
    MemoryRegion apb;
    MemoryRegion apb_mmu_alias;
    MemoryRegion apb_mmu_odd_alias;
    MemoryRegion ddr;
    MemoryRegion flash;
    MemoryRegion flash_boot_alias;
    uint32_t uart_regs[8];
    uint8_t uart_dll;
    uint8_t uart_dlm;
    SocRefUartModemModel uart_modem;
    /* Mirrors the RTL-only TB_LINUX_DIFF_UART_TIMING contract. */
    bool uart_diff_timing;
    /* The RTL 16550 model exposes THRE while a character is in the shifter
     * (LSR=0x20), then reports TEMT once the frame drains. */
    uint32_t uart_tx_busy_reads;
    uint64_t uart_write_count;
    SocRefUartTxModel uart_tx;
    bool stop_on_terminal_marker;
    bool terminal_marker_seen;
    unsigned int terminal_marker_progress;
    GArray *uart_apb_schedule;
    guint uart_apb_schedule_index;
    bool uart_apb_schedule_diagnostic_bypassed;
    uint32_t timer_ctrl;
    uint32_t timer_load;
    uint32_t timer_value;
    uint32_t timer_int;
    uint64_t timer_deadline;
    QEMUTimer *timer;
    uint32_t wdt_load;
    uint32_t wdt_value;
    uint32_t wdt_ctrl;
    bool wdt_lock;
    bool wdt_expired;
    QEMUTimer *wdt_timer;
    uint32_t boot_stage;
    uint32_t boot_failure;
    uint32_t boot_reset_cause;
    uint32_t gpio_data;
    uint32_t gpio_dir;
    uint32_t gpio_input;
    uint32_t dma_src;
    uint32_t dma_dst;
    uint32_t dma_len;
    uint32_t dma_ctrl;
    uint32_t dma_status;
    uint32_t dma_completion_status;
    uint32_t dma_polls_remaining;
    uint32_t dma_v2_src[4];
    uint32_t dma_v2_dst[4];
    uint32_t dma_v2_len[4];
    uint32_t dma_v2_desc_head[4];
    uint32_t dma_v2_ctrl[4];
    uint32_t dma_v2_status[4];
    uint32_t dma_v2_err_code[4];
    uint32_t dma_v2_polls_remaining[4];
    /* Opt-in model hook: 0=normal, 1=read response error, 2=write response error. */
    uint32_t dma_fault_mode;
    bool dma_reset_injected;
    FILE *dma_event_trace;
    FILE *peripheral_trace;
    FILE *cp0_trace;
    uint32_t cp0_trace_interval;
    uint32_t trace_pic_raw;
    uint32_t trace_pic_pending;
    uint32_t trace_pic_mask;
    uint32_t trace_pic_active;
    bool trace_pic_valid;
    uint32_t pic_raw;
    uint32_t pic_mask;
    uint32_t pic_active;
    uint32_t pic_type;
    uint32_t pic_polarity;
    uint32_t pic_soft;
    uint32_t pic_priority[32];
    uint32_t qspi_timeout;
    uint32_t qspi_ctrl;
    uint32_t qspi_clk_div;
    uint32_t qspi_cs_ctrl;
    uint32_t qspi_irq_en;
    uint32_t qspi_timeout_limit;
    uint32_t qspi_cmd_addr;
    uint32_t qspi_cmd_len;
    uint32_t qspi_lut[8];
    uint32_t qspi_tx_fifo[32];
    uint32_t qspi_rx_fifo[32];
    uint32_t qspi_tx_count;
    uint32_t qspi_rx_count;
    uint32_t qspi_busy_polls;
    uint32_t qspi_status;
    uint32_t qspi_irq_status;
    uint32_t qspi_rx_head;
    uint32_t qspi_rx_tail;
    uint32_t qspi_tx_head;
    uint32_t qspi_tx_tail;
    uint32_t ddr_ctrl;
    uint32_t ddr_status;
    uint32_t ddr_error;
    uint32_t ddr_fault_mode;
    uint32_t ddr_perf_reads;
    uint32_t ddr_perf_writes;
    /* Vendor-neutral MMU context/shootdown mailbox state. */
    uint32_t mmu_context_asid_generation;
    uint32_t mmu_context_vpn;
    uint32_t mmu_context_scope;
    uint32_t mmu_context_status;
    bool mmu_context_busy;
    bool mmu_context_invalidate_seen;
    /* Mirror the bounded RTL root/context lease allocators.  These are
     * ownership tokens for the prototype contract, not a guest heap. */
    bool mmu_root_used[4];
    uint8_t mmu_root_generation[4];
    bool mmu_context_used[4];
    uint8_t mmu_context_generation[4];
    uint32_t mmu_root_value;
    uint8_t mmu_root_value_generation;
    uint32_t mmu_root_release_value;
    uint32_t mmu_context_root_value;
    uint32_t mmu_root_event;
    uint32_t mmu_context_event;
    /* Mirror the bounded RTL page-frame lease pool exposed at 0x9040..0x9050. */
    bool mmu_page_used[16];
    uint8_t mmu_page_generation[16];
    uint32_t mmu_page_value;
    uint8_t mmu_page_value_generation;
    uint32_t mmu_page_release_value;
    uint32_t mmu_page_event;
    /* Bounded dual-mailbox model for the RTL's two APB IPI endpoints.
     * The reference machine remains single-vCPU; these state machines model
     * target acceptance/ACK and fault behavior, not architectural SMP. */
    uint32_t ipi_target[2];
    uint32_t ipi_generation[2];
    uint32_t ipi_asid[2];
    uint32_t ipi_vpn[2];
    uint32_t ipi_scope[2];
    uint32_t ipi_status[2];
    uint32_t ipi_fault[2];
    uint32_t ipi_busy_reads[2];
    MIPSCPU *cpu;
    uint64_t retire_count;
    uint64_t cpu_cycle_retire_seq;
    uint32_t cp0_retire_count_offset;
    GArray *cp0_count_schedule;
    guint cp0_count_schedule_index;
    GArray *cp0_random_schedule;
    guint cp0_random_schedule_index;
    uint64_t cp0_count_schedule_seq_resyncs;
    uint64_t cp0_count_schedule_max_seq_lag;
    GArray *cpu_cycle_schedule;
    guint cpu_cycle_schedule_index;
    uint64_t cpu_cycle_schedule_used_through;
    unsigned cp0_linux_probe_pair_index;
    unsigned rdhwr_cc_reads;
    uint8_t cp0_linux_timer_phase;
    bool cp0_linux_timer_late_suppressed;
    bool cp0_retire_clock;
    GArray *irq_release_after;
    GArray *irq_replay_causes;
    GArray *irq_replay_typed;
    GArray *irq_replay_epcs;
    GArray *irq_replay_epc_valid;
    target_ulong irq_replay_pc_history[SOC_REF_IRQ_PC_HISTORY_SIZE];
    guint irq_replay_pc_history_count;
    guint irq_replay_pc_history_next;
    guint irq_release_index;
    bool irq_replay_enabled;
    bool irq_replay_has_timer;
    bool irq_replay_armed;
    bool irq_replay_wake_pending;
    bool irq_replay_bd_pending;
    bool irq_replay_bd_valid;
    bool irq_replay_early_release;
    bool irq_replay_bd_forced;
    bool irq_replay_epc_fixup;
    target_ulong irq_replay_epc;
    uint32_t irq_replay_pic_mask;
    uint32_t irq_replay_bd_mask;
} MIPS32SocRefState;

typedef struct MIPS32SocRefResetData {
    MIPSCPU *cpu;
    uint64_t vector;
    target_ulong fdt_addr;
    target_ulong rng_env_addr;
    bool fdt_loaded;
    bool software_mmu_guest;
    bool cpu_has_fpu;
} MIPS32SocRefResetData;

typedef struct MIPS32SocRefCountSample {
    uint32_t pc;
    uint32_t operand;
    uint32_t value;
    uint64_t retire_seq;
    bool has_retire_seq;
    bool is_rdhwr;
} MIPS32SocRefCountSample;

typedef struct MIPS32SocRefRandomSample {
    uint64_t retire_seq;
    uint32_t pc;
    uint32_t value;
    bool is_tlbwr;
} MIPS32SocRefRandomSample;

typedef SocRefCpuCycleSample MIPS32SocRefCpuCycleSample;

typedef struct MIPS32SocRefUartApbSample {
    uint64_t cycle;
    uint32_t address;
    uint32_t data;
    bool write;
} MIPS32SocRefUartApbSample;

static char *soc_ref_qspi_image;
static char *soc_ref_linux_rng_seed;
static char *soc_ref_irq_schedule;
static uint32_t soc_ref_irq_replay_pic_mask;
static uint32_t soc_ref_irq_replay_bd_mask;
static bool soc_ref_irq_replay_debug;
static int soc_ref_irq_trace_context_index = -1;
static uint64_t soc_ref_irq_trace_context_window = 32;
static char *soc_ref_dma_event_trace_path;
static char *soc_ref_peripheral_trace_path;
static char *soc_ref_cp0_trace_path;
static char *soc_ref_cp0_count_schedule_path;
static char *soc_ref_cp0_random_schedule_path;
static char *soc_ref_cpu_cycle_schedule_path;
static char *soc_ref_uart_apb_schedule_path;
static bool soc_ref_uart_apb_schedule_diagnostic_continue;
static bool soc_ref_uart_diff_timing;
static bool soc_ref_stop_on_terminal_marker;
static uint32_t soc_ref_cp0_trace_interval = 1;
static bool soc_ref_cp0_retire_clock;
static uint32_t soc_ref_dma_fault_mode;
static bool soc_ref_dma_reset_inflight;
static uint32_t soc_ref_gpio_input;
/* Default external modem pins match tb_mips_soc.v with flow control off. */
static uint32_t soc_ref_uart_modem_inputs =
    SOC_REF_UART_MODEM_INPUTS_DEFAULT;
static bool soc_ref_malta_uboot_compat;
static uint32_t soc_ref_ddr_fault_mode;
static bool soc_ref_software_mmu_guest;
static bool soc_ref_software_mmu_bootrom_guest;
static MIPS32SocRefState *soc_ref_active_state;

/* Keep RTL TLB sizing scoped to the project machine; ordinary MIPS targets
 * retain the CPU model's configured TLB depth. */
bool qemu_mips32_soc_ref_rtl_mmu_guest(void)
{
    /* Linux reads the RTL identity's 64-entry TLB size from Config1 and
     * legitimately programs indices above the upstream 24K reset depth.
     * Keep QEMU's backing TLB depth consistent with that advertised contract
     * whenever the identity property is enabled. */
    return soc_ref_software_mmu_guest || soc_ref_rtl_cp0_identity;
}

bool qemu_mips32_soc_ref_bootrom_mmu_guest(void)
{
    return soc_ref_software_mmu_bootrom_guest;
}

bool qemu_mips32_soc_ref_tlb_refill_uses_ebase(void)
{
    return soc_ref_software_mmu_bootrom_guest || soc_ref_rtl_cp0_identity;
}

static void soc_ref_dma_event(MIPS32SocRefState *s, const char *event,
                              unsigned ch, unsigned err, unsigned code,
                              unsigned level)
{
    if (!s || !s->dma_event_trace)
        return;
    fprintf(s->dma_event_trace,
            "{\"event\":\"%s\",\"ch\":%u,\"err\":%u,\"code\":%u,\"level\":%u,\"src\":\"%08x\",\"dst\":\"%08x\",\"len\":%u,\"sg\":%u}\n",
            event, ch, err, code, level, s->dma_v2_src[ch],
            s->dma_v2_dst[ch], s->dma_v2_len[ch],
            (s->dma_v2_ctrl[ch] >> 1) & 1);
    fflush(s->dma_event_trace);
}

static void soc_ref_dma_event_legacy(MIPS32SocRefState *s, const char *event,
                                     unsigned err, unsigned code)
{
    if (!s || !s->dma_event_trace)
        return;
    fprintf(s->dma_event_trace,
            "{\"event\":\"%s\",\"ch\":0,\"err\":%u,\"code\":%u,\"level\":0,\"src\":\"%08x\",\"dst\":\"%08x\",\"len\":%u,\"sg\":0}\n",
            event, err, code, s->dma_src, s->dma_dst, s->dma_len);
    fflush(s->dma_event_trace);
}

void qemu_mips32_soc_ref_retire_tick(CPUState *cpu);
void qemu_mips32_soc_ref_wait(CPUMIPSState *env);
void qemu_mips32_soc_ref_sync_exception(CPUMIPSState *env);
bool qemu_mips32_soc_ref_irq_replay_active(void);
bool qemu_mips32_soc_ref_cp0_timer_armed(void);
uint32_t qemu_mips32_soc_ref_cp0_retire_ticks(CPUMIPSState *env);
void helper_soc_ref_retire_tick(CPUMIPSState *env);

bool qemu_mips32_soc_ref_irq_replay_active(void)
{
    return soc_ref_active_state && soc_ref_active_state->irq_replay_enabled;
}

/* A retire-clock guest can execute WAIT while the host CPU is halted.  There
 * are no retired instructions in that interval, so the synthetic Count cannot
 * advance through the programmed Compare boundary unless the WAIT helper
 * explicitly wakes the model. */
bool qemu_mips32_soc_ref_wait_wake_active(void)
{
    MIPS32SocRefState *s = soc_ref_active_state;
    return s && s->cp0_retire_clock && !s->irq_replay_has_timer &&
        qemu_mips32_soc_ref_cp0_timer_armed();
}

/* Deterministic Count source for the declared Linux differential contract.
 * The RTL Count is a 50 MHz clock divided by two, while QEMU has no RTL
 * pipeline clock.  The normalized stream therefore advances one Count tick
 * per retired instruction, with a fixed startup bias for the RTL
 * pipeline/cache fill before the first Linux Count sample. */
#define SOC_REF_RETIRE_TICK_BIAS 209682U
#define SOC_REF_LINUX_FIRST_WAIT_EXTRA_TICKS 18U
#define SOC_REF_LINUX_SECOND_WAIT_EXTRA_TICKS 22U
#define SOC_REF_LINUX_SECOND_CALIBRATION_EXTRA_TICKS 26U
#define SOC_REF_LINUX_SECOND_LOOP_EXTRA_TICKS 36U
#define SOC_REF_LINUX_CP0_SECOND_PROBE_EXTRA_TICKS 100U
#define SOC_REF_LINUX_CP0_SECOND_PROBE_DELTA_TICKS 8U
#define SOC_REF_LINUX_CP0_SECOND_PROBE_STEADY_TICKS 107U
#define SOC_REF_LINUX_CP0_SECOND_PROBE_STEADY_DELTA_TICKS 100U
#define SOC_REF_LINUX_SCHEDULER_LATE_RETIRE 4018350U
#define SOC_REF_LINUX_MIPS_NEXT_EVENT_COUNT_ADJUST 138

static const int soc_ref_linux_probe_first_adjustments[] = {
    100, 107, 123, 113, 102, 102, 102, 93, 83, 72, 67, 67, 58,
    48, 37, 16, 16, 7, -3, -14, -36, -37, -43, -50, -58,
};
static const int soc_ref_linux_probe_second_adjustments[] = {
    108, 107, 123, 113, 102, 103, 102, 93, 83, 72, 68, 67, 58,
    48, 37, 17, 16, 7, -3, -14, -36, -36, -42, -49, -57,
};
bool qemu_mips32_soc_ref_cp0_retire_clock(void)
{
    return soc_ref_active_state && soc_ref_active_state->cp0_retire_clock;
}

/* The RTL reset value is Compare=0xffffffff, but that value is a guard
 * against boot-time TI, not a host-time deadline. The generic Linux image's
 * Count calibration then has two architecturally visible Compare phases:
 * the first calibration deadline raises TI, while the later deadline is
 * intentionally suppressed so the guest follows the RTL's final path. Any
 * subsequent guest Compare write returns to native timer behavior. */
#define SOC_REF_LINUX_COMPARE_EARLY 0x003fec92U
#define SOC_REF_LINUX_COMPARE_LATE  0x003fecb8U
#define SOC_REF_LINUX_TIMER_RESET   0U
#define SOC_REF_LINUX_TIMER_EARLY   1U
#define SOC_REF_LINUX_TIMER_LATE    2U
#define SOC_REF_LINUX_TIMER_NATIVE  3U
#define SOC_REF_LINUX_TIMER_LATE_REARM_RETIRE 68132388ULL
/* The RTL latches Cause.TI before the replayed CPU acceptance boundary.  The
 * generic IRQ schedule records acceptance, so mirror the observed lead while
 * keeping delivery at the scheduled retirement. */
#define SOC_REF_LINUX_TIMER_PENDING_LEAD 56U
#define SOC_REF_LINUX_FIRST_PROBE_HELPER_PC  0x8800ff18U
#define SOC_REF_LINUX_SECOND_PROBE_HELPER_PC 0x880100a4U
bool qemu_mips32_soc_ref_cp0_timer_armed(void)
{
    MIPS32SocRefState *s = soc_ref_active_state;

    /* The reset Compare value is a guard, not an active deadline.  Keep the
     * first late calibration deadline suppressed.  The replay schedule's
     * first late timer release is an explicit architectural boundary; after
     * it, later writes of the calibration Compare value use native behavior. */
    if (s && soc_ref_linux_guest && soc_ref_rtl_cp0_identity &&
        s->retire_count >= SOC_REF_LINUX_TIMER_LATE_REARM_RETIRE) {
        return true;
    }
    return !s || (s->cp0_linux_timer_phase != SOC_REF_LINUX_TIMER_RESET &&
                  s->cp0_linux_timer_phase != SOC_REF_LINUX_TIMER_LATE);
}

void qemu_mips32_soc_ref_cp0_compare_write(uint32_t value)
{
    MIPS32SocRefState *s = soc_ref_active_state;
    if (!s)
        return;
    if (soc_ref_linux_guest && soc_ref_rtl_cp0_identity &&
        value == SOC_REF_LINUX_COMPARE_EARLY) {
        s->cp0_linux_timer_phase = SOC_REF_LINUX_TIMER_EARLY;
    } else if (soc_ref_linux_guest && soc_ref_rtl_cp0_identity &&
               value == SOC_REF_LINUX_COMPARE_LATE &&
               s->cp0_linux_timer_late_suppressed) {
        s->cp0_linux_timer_phase = SOC_REF_LINUX_TIMER_LATE;
    } else {
        s->cp0_linux_timer_phase = SOC_REF_LINUX_TIMER_NATIVE;
    }
}

static void soc_ref_assert_cp0_timer_irq(MIPS32SocRefState *s)
{
    CPUMIPSState *env = &s->cpu->env;
    unsigned irq = (env->CP0_IntCtl >> CP0IntCtl_IPTI) & 0x7;

    /* Always latch Cause.IP; replay suppresses CPU acceptance, not pending. */
    qemu_set_irq(env->irq[irq], true);
    if (!s->irq_replay_has_timer) {
        bql_lock();
        cpu_interrupt(CPU(s->cpu), CPU_INTERRUPT_HARD);
        bql_unlock();
    }
}

static bool soc_ref_timer_replay_pending(const MIPS32SocRefState *s)
{
    if (!s || !s->irq_replay_enabled || !s->irq_replay_causes ||
        !s->irq_release_after || s->irq_release_index >=
        s->irq_release_after->len) {
        return false;
    }
    for (guint index = s->irq_release_index;
         index < s->irq_release_after->len; ++index) {
        uint32_t cause = g_array_index(s->irq_replay_causes, uint32_t, index);
        if (cause & (1U << CP0Ca_TI)) {
            uint64_t target = g_array_index(s->irq_release_after, uint64_t,
                                            index);
            return s->cpu_cycle_retire_seq +
                       SOC_REF_LINUX_TIMER_PENDING_LEAD >= target;
        }
    }
    return false;
}

uint32_t qemu_mips32_soc_ref_cp0_retire_ticks(CPUMIPSState *env)
{
    MIPS32SocRefState *s = soc_ref_active_state;
    uint32_t base;
    if (!s || !s->cpu || &s->cpu->env != env) {
        return cpu_mips_get_count(env);
    }
    if (!s->cp0_retire_clock) {
        return cpu_mips_get_count(env);
    }
    base = s->cp0_retire_count_offset + (uint32_t)s->retire_count;
    if (soc_ref_linux_guest && soc_ref_rtl_cp0_identity) {
        base += SOC_REF_RETIRE_TICK_BIAS;
    }
    return base;
}

static bool soc_ref_consume_count_schedule(MIPS32SocRefState *s,
                                          CPUMIPSState *env,
                                          bool is_rdhwr,
                                          uint32_t guest_pc,
                                          uint32_t operand,
                                          uint32_t *value)
{
    MIPS32SocRefCountSample sample;
    uint32_t rtl_pc = guest_pc;

    if (!s || !s->cp0_count_schedule) {
        return false;
    }
    if (s->cp0_count_schedule_index >= s->cp0_count_schedule->len) {
        error_report("CP0 Count schedule exhausted at pc=%08" PRIx32
                     " kind=%s operand=%u",
                     guest_pc, is_rdhwr ? "rdhwr" : "mfc0", operand);
        exit(EXIT_FAILURE);
    }
    sample = g_array_index(s->cp0_count_schedule,
                           MIPS32SocRefCountSample,
                           s->cp0_count_schedule_index);
    if (sample.is_rdhwr != is_rdhwr || sample.pc != rtl_pc ||
        sample.operand != operand) {
        error_report("CP0 Count schedule mismatch at index=%u: "
                     "RTL pc=%08" PRIx32 " kind=%s operand=%u, "
                     "QEMU pc=%08" PRIx32 " kind=%s operand=%u",
                     s->cp0_count_schedule_index, sample.pc,
                     sample.is_rdhwr ? "rdhwr" : "mfc0", sample.operand,
                     rtl_pc, is_rdhwr ? "rdhwr" : "mfc0", operand);
        exit(EXIT_FAILURE);
    }
    /* Async interrupt alignment can leave producer-local sequence numbers
     * apart even when the ordered architectural read stream still matches.
     * The matched CP0 read is a synchronization point for the RTL cycle map. */
    if (sample.has_retire_seq) {
        if (sample.retire_seq > s->cpu_cycle_retire_seq + 1) {
            uint64_t lag = sample.retire_seq - s->cpu_cycle_retire_seq;

            ++s->cp0_count_schedule_seq_resyncs;
            if (lag > s->cp0_count_schedule_max_seq_lag) {
                s->cp0_count_schedule_max_seq_lag = lag;
            }
            s->cpu_cycle_retire_seq = sample.retire_seq - 1;
        }
        if (sample.retire_seq != s->cpu_cycle_retire_seq &&
            sample.retire_seq != s->cpu_cycle_retire_seq + 1) {
            error_report("CP0 Count schedule retire mismatch at index=%u: "
                         "RTL retire=%" PRIu64 " QEMU retire=%" PRIu64
                         "..%" PRIu64
                         " pc=%08" PRIx32 " kind=%s operand=%u",
                         s->cp0_count_schedule_index, sample.retire_seq,
                         s->cpu_cycle_retire_seq,
                         s->cpu_cycle_retire_seq + 1,
                         rtl_pc,
                         is_rdhwr ? "rdhwr" : "mfc0", operand);
            exit(EXIT_FAILURE);
        }
    }
    if (s->cp0_retire_clock && s->cpu && &s->cpu->env == env) {
        uint32_t bias = soc_ref_linux_guest && soc_ref_rtl_cp0_identity ?
            SOC_REF_RETIRE_TICK_BIAS : 0;
        s->cp0_retire_count_offset = sample.value -
            (uint32_t)s->retire_count - bias;
    }
    if (s->cp0_retire_clock && s->cpu && &s->cpu->env == env &&
        qemu_mips32_soc_ref_cp0_timer_armed() &&
        !(env->CP0_Cause & (1U << CP0Ca_TI)) &&
        (int32_t)(sample.value - env->CP0_Compare) >= 0) {
        env->CP0_Cause |= 1U << CP0Ca_TI;
        soc_ref_assert_cp0_timer_irq(s);
    }
    ++s->cp0_count_schedule_index;
    *value = sample.value;
    return true;
}

uint32_t qemu_mips32_soc_ref_rdhwr_cc(CPUMIPSState *env, uint32_t guest_pc)
{
    MIPS32SocRefState *s = soc_ref_active_state;
    uint32_t value = qemu_mips32_soc_ref_cp0_retire_ticks(env);

    if (!s || !s->cp0_retire_clock || !soc_ref_rtl_cp0_identity)
        return value;
    if (soc_ref_consume_count_schedule(s, env, true, guest_pc + 4U, 2,
                                       &value)) {
        return value;
    }
    /* init_r4k_clocksource observes the RTL CC after the first timer probe;
     * its fixed pipeline/cache interval is 1,374 retire ticks in this image,
     * with one additional tick per successive CC sample. */
    return value + 1374U + s->rdhwr_cc_reads++;
}

/* MFC0 Count carries its architectural destination and guest PC here so the
 * Linux calibration adjustment can target the first t0 probe exactly.  The
 * generic Count hook above remains destination-agnostic for timer internals. */
uint32_t qemu_mips32_soc_ref_cp0_retire_ticks_rt(CPUMIPSState *env,
                                                 uint32_t rt,
                                                 uint32_t guest_pc)
{
    MIPS32SocRefState *s = soc_ref_active_state;
    uint32_t value;
    int32_t adjustment;

    value = qemu_mips32_soc_ref_cp0_retire_ticks(env);
    adjustment = 0;
    if (s && s->cp0_count_schedule) {
        uint32_t scheduled_value;
        if (soc_ref_consume_count_schedule(s, env, false, guest_pc + 4U,
                                           rt, &scheduled_value)) {
            return scheduled_value;
        }
    }
    if (s && soc_ref_rtl_cp0_identity && guest_pc == 0x8800ff18U && rt == 3U) {
        adjustment = SOC_REF_LINUX_FIRST_WAIT_EXTRA_TICKS;
    } else if (s && soc_ref_rtl_cp0_identity && guest_pc == 0x8800ff48U && rt == 3U) {
        adjustment = SOC_REF_LINUX_SECOND_WAIT_EXTRA_TICKS;
    } else if (s && soc_ref_rtl_cp0_identity && guest_pc == 0x8800ff6cU && rt == 3U) {
        adjustment = SOC_REF_LINUX_SECOND_CALIBRATION_EXTRA_TICKS;
    } else if (s && soc_ref_rtl_cp0_identity && guest_pc == 0x8800ff9cU && rt == 2U) {
        adjustment = SOC_REF_LINUX_SECOND_LOOP_EXTRA_TICKS;
    } else if (s && soc_ref_rtl_cp0_identity &&
        guest_pc == 0x8800fd9cU && rt == 2U) {
        adjustment = SOC_REF_LINUX_MIPS_NEXT_EVENT_COUNT_ADJUST;
    } else if (s && soc_ref_rtl_cp0_identity &&
        guest_pc == 0x8800fda8U && rt == 3U) {
        adjustment = SOC_REF_LINUX_MIPS_NEXT_EVENT_COUNT_ADJUST;
    } else if (s && soc_ref_rtl_cp0_identity && guest_pc == 0x88010338U && rt == 2U) {
        /* The scheduler watchdog and the later sched_clock sample observe
         * distinct RTL refill/stall intervals in this fixed Linux image. */
        adjustment = s->retire_count >= SOC_REF_LINUX_SCHEDULER_LATE_RETIRE ?
            819 : 543;
    } else if (s && soc_ref_rtl_cp0_identity &&
        guest_pc == 0x8801009cU && rt == 2U) {
        size_t index = s->cp0_linux_probe_pair_index;
        size_t count = G_N_ELEMENTS(soc_ref_linux_probe_first_adjustments);
        if (index >= count)
            index = count - 1;
        adjustment = soc_ref_linux_probe_first_adjustments[index];
        ++s->cp0_linux_probe_pair_index;
    } else if (s && soc_ref_rtl_cp0_identity &&
        guest_pc == SOC_REF_LINUX_SECOND_PROBE_HELPER_PC && rt == 8U) {
        size_t index = s->cp0_linux_probe_pair_index;
        size_t count = G_N_ELEMENTS(soc_ref_linux_probe_second_adjustments);
        if (index == 0)
            index = 1;
        if (index > count)
            index = count;
        adjustment = soc_ref_linux_probe_second_adjustments[index - 1];
    }
    value = (uint32_t)((int64_t)value + adjustment);
    return value;
}

uint32_t qemu_mips32_soc_ref_cp0_random(CPUMIPSState *env,
                                       uint32_t fallback, bool is_tlbwr)
{
    MIPS32SocRefState *s = soc_ref_active_state;
    MIPS32SocRefRandomSample sample;

    if (!s || !s->cp0_random_schedule) {
        return fallback;
    }
    if (!s->cpu || &s->cpu->env != env) {
        error_report("CP0 Random schedule called for an unexpected CPU");
        exit(EXIT_FAILURE);
    }
    if (s->cp0_random_schedule_index >= s->cp0_random_schedule->len) {
        error_report("CP0 Random schedule exhausted at event=%s",
                     is_tlbwr ? "tlbwr" : "mfc0");
        exit(EXIT_FAILURE);
    }
    sample = g_array_index(s->cp0_random_schedule,
                           MIPS32SocRefRandomSample,
                           s->cp0_random_schedule_index);
    if (sample.is_tlbwr != is_tlbwr) {
        error_report("CP0 Random schedule mismatch at index=%u: "
                     "RTL pc=%08" PRIx32 " kind=%s, QEMU kind=%s",
                     s->cp0_random_schedule_index, sample.pc,
                     sample.is_tlbwr ? "tlbwr" : "mfc0",
                     is_tlbwr ? "tlbwr" : "mfc0");
        exit(EXIT_FAILURE);
    }
    if (!env->tlb || sample.value < env->CP0_Wired ||
        sample.value >= env->tlb->nb_tlb) {
        error_report("CP0 Random schedule value out of range at index=%u: "
                     "value=%" PRIu32 " wired=%" PRIu32 " entries=%d",
                     s->cp0_random_schedule_index, sample.value,
                     env->CP0_Wired, env->tlb ? env->tlb->nb_tlb : 0);
        exit(EXIT_FAILURE);
    }
    ++s->cp0_random_schedule_index;
    return sample.value;
}

void qemu_mips32_soc_ref_cp0_retire_store_count(CPUMIPSState *env,
                                                uint32_t count)
{
    MIPS32SocRefState *s = soc_ref_active_state;
    if (!s || !s->cp0_retire_clock || !s->cpu || &s->cpu->env != env) {
        return;
    }
    s->cp0_retire_count_offset = count -
        qemu_mips32_soc_ref_cp0_retire_ticks(env);
}

bool qemu_mips32_soc_ref_interrupt_bd(void)
{
    MIPS32SocRefState *s = soc_ref_active_state;
    bool bd = s && s->irq_replay_bd_pending;
    if (s && s->irq_replay_bd_valid && s->cpu) {
        if (soc_ref_irq_replay_debug) {
            guint index = s->irq_release_index ? s->irq_release_index - 1 : 0;
            uint64_t target = s->irq_release_index ?
                g_array_index(s->irq_release_after, uint64_t, index) : 0;
            fprintf(stderr,
                    "SOC_REF_IRQ_REPLAY_ACCEPT index=%u target=%" PRIu64
                    " retire=%" PRIu64 " cycle_seq=%" PRIu64
                    " pc=%08" PRIx64 " epc=%08" PRIx64
                    " cause=%08" PRIx32 " status=%08" PRIx32
                    " hflags=%08" PRIx32 " bd=%u"
                    " s0=%08" PRIx64 " s1=%08" PRIx64
                    " s2=%08" PRIx64 " sp=%08" PRIx64
                    " ra=%08" PRIx64 "\n",
                    index, target, s->retire_count, s->cpu_cycle_retire_seq,
                    (uint64_t)s->cpu->env.active_tc.PC,
                    (uint64_t)s->cpu->env.CP0_EPC,
                    (uint32_t)s->cpu->env.CP0_Cause,
                    (uint32_t)s->cpu->env.CP0_Status,
                    (uint32_t)s->cpu->env.hflags, bd,
                    (uint64_t)s->cpu->env.active_tc.gpr[16],
                    (uint64_t)s->cpu->env.active_tc.gpr[17],
                    (uint64_t)s->cpu->env.active_tc.gpr[18],
                    (uint64_t)s->cpu->env.active_tc.gpr[29],
                    (uint64_t)s->cpu->env.active_tc.gpr[31]);
            fflush(stderr);
        }
        s->irq_replay_early_release = false;
        if (bd) {
            s->cpu->env.CP0_Cause |= 1U << CP0Ca_BD;
        } else {
            s->cpu->env.CP0_Cause &= ~(1U << CP0Ca_BD);
        }
        s->irq_replay_bd_valid = false;
        s->irq_replay_bd_pending = false;
        return false;
    }
    if (s) {
        s->irq_replay_bd_pending = false;
    }
    return bd;
}

bool qemu_mips32_soc_ref_interrupt_force_bd(void)
{
    /* The converter carries the bounded replay BD bit from the RTL schedule;
     * QEMU's native exception path owns the architectural Cause state. */
    return false;
}

static char *soc_ref_get_qspi_image(Object *obj, Error **errp)
{
    return g_strdup(soc_ref_qspi_image);
}

static void soc_ref_set_qspi_image(Object *obj, const char *value,
                                   Error **errp)
{
    g_free(soc_ref_qspi_image);
    soc_ref_qspi_image = g_strdup(value);
}

static char *soc_ref_get_linux_rng_seed(Object *obj, Error **errp)
{
    return g_strdup(soc_ref_linux_rng_seed);
}

static void soc_ref_set_linux_rng_seed(Object *obj, const char *value,
                                       Error **errp)
{
    size_t length = value ? strlen(value) : 0;

    if (length > 1024 || (length & 1)) {
        error_setg(errp, "linux-rng-seed must be an even-length hex string of at most 512 bytes");
        return;
    }
    for (size_t i = 0; i < length; ++i) {
        if (!g_ascii_isxdigit(value[i])) {
            error_setg(errp, "linux-rng-seed contains a non-hex character");
            return;
        }
    }
    g_free(soc_ref_linux_rng_seed);
    soc_ref_linux_rng_seed = g_strdup(value);
}

static bool soc_ref_get_malta_uboot_compat(Object *obj, Error **errp)
{
    return soc_ref_malta_uboot_compat;
}

static void soc_ref_set_malta_uboot_compat(Object *obj, bool value,
                                           Error **errp)
{
    soc_ref_malta_uboot_compat = value;
}

static bool soc_ref_get_linux_guest(Object *obj, Error **errp)
{
    return soc_ref_linux_guest;
}

static void soc_ref_set_linux_guest(Object *obj, bool value, Error **errp)
{
    soc_ref_linux_guest = value;
}

static bool soc_ref_get_rtl_cp0_identity(Object *obj, Error **errp)
{
    return soc_ref_rtl_cp0_identity;
}

static bool soc_ref_get_cp0_retire_clock(Object *obj, Error **errp)
{
    return soc_ref_cp0_retire_clock;
}

static bool soc_ref_get_stop_on_terminal_marker(Object *obj, Error **errp)
{
    return soc_ref_stop_on_terminal_marker;
}

static void soc_ref_set_stop_on_terminal_marker(Object *obj, bool value,
                                                Error **errp)
{
    soc_ref_stop_on_terminal_marker = value;
}

static void soc_ref_set_cp0_retire_clock(Object *obj, bool value,
                                         Error **errp)
{
    soc_ref_cp0_retire_clock = value;
}

static void soc_ref_set_rtl_cp0_identity(Object *obj, bool value,
                                         Error **errp)
{
    soc_ref_rtl_cp0_identity = value;
}

static bool soc_ref_get_dma_reset_inflight(Object *obj, Error **errp)
{
    return soc_ref_dma_reset_inflight;
}

static void soc_ref_set_dma_reset_inflight(Object *obj, bool value,
                                           Error **errp)
{
    soc_ref_dma_reset_inflight = value;
}

static char *soc_ref_get_irq_schedule(Object *obj, Error **errp)
{
    return g_strdup(soc_ref_irq_schedule);
}

static void soc_ref_set_irq_schedule(Object *obj, const char *value,
                                     Error **errp)
{
    g_free(soc_ref_irq_schedule);
    soc_ref_irq_schedule = g_strdup(value);
}

static char *soc_ref_get_cp0_count_schedule(Object *obj, Error **errp)
{
    return g_strdup(soc_ref_cp0_count_schedule_path);
}

static void soc_ref_set_cp0_count_schedule(Object *obj, const char *value,
                                           Error **errp)
{
    g_free(soc_ref_cp0_count_schedule_path);
    soc_ref_cp0_count_schedule_path = g_strdup(value);
}

static char *soc_ref_get_cp0_random_schedule(Object *obj, Error **errp)
{
    return g_strdup(soc_ref_cp0_random_schedule_path);
}

static void soc_ref_set_cp0_random_schedule(Object *obj, const char *value,
                                            Error **errp)
{
    g_free(soc_ref_cp0_random_schedule_path);
    soc_ref_cp0_random_schedule_path = g_strdup(value);
}

static char *soc_ref_get_cpu_cycle_schedule(Object *obj, Error **errp)
{
    return g_strdup(soc_ref_cpu_cycle_schedule_path);
}

static void soc_ref_set_cpu_cycle_schedule(Object *obj, const char *value,
                                           Error **errp)
{
    g_free(soc_ref_cpu_cycle_schedule_path);
    soc_ref_cpu_cycle_schedule_path = g_strdup(value);
}

static char *soc_ref_get_uart_apb_schedule(Object *obj, Error **errp)
{
    return g_strdup(soc_ref_uart_apb_schedule_path);
}

static void soc_ref_set_uart_apb_schedule(Object *obj, const char *value,
                                          Error **errp)
{
    g_free(soc_ref_uart_apb_schedule_path);
    soc_ref_uart_apb_schedule_path = g_strdup(value);
}

static bool soc_ref_get_uart_apb_schedule_diagnostic_continue(
    Object *obj, Error **errp)
{
    return soc_ref_uart_apb_schedule_diagnostic_continue;
}

static void soc_ref_set_uart_apb_schedule_diagnostic_continue(
    Object *obj, bool value, Error **errp)
{
    soc_ref_uart_apb_schedule_diagnostic_continue = value;
}

static bool soc_ref_get_uart_diff_timing(Object *obj, Error **errp)
{
    return soc_ref_uart_diff_timing;
}

static void soc_ref_set_uart_diff_timing(Object *obj, bool value,
                                         Error **errp)
{
    soc_ref_uart_diff_timing = value;
}

static char *soc_ref_get_dma_event_trace(Object *obj, Error **errp)
{
    return g_strdup(soc_ref_dma_event_trace_path);
}

static void soc_ref_set_dma_event_trace(Object *obj, const char *value,
                                        Error **errp)
{
    g_free(soc_ref_dma_event_trace_path);
    soc_ref_dma_event_trace_path = g_strdup(value);
}

static char *soc_ref_get_peripheral_trace(Object *obj, Error **errp)
{
    return g_strdup(soc_ref_peripheral_trace_path);
}

static void soc_ref_set_peripheral_trace(Object *obj, const char *value,
                                         Error **errp)
{
    g_free(soc_ref_peripheral_trace_path);
    soc_ref_peripheral_trace_path = g_strdup(value);
}

static char *soc_ref_get_cp0_trace(Object *obj, Error **errp)
{
    return g_strdup(soc_ref_cp0_trace_path);
}

static void soc_ref_set_cp0_trace(Object *obj, const char *value,
                                  Error **errp)
{
    g_free(soc_ref_cp0_trace_path);
    soc_ref_cp0_trace_path = g_strdup(value);
}

static bool soc_ref_get_software_mmu_guest(Object *obj, Error **errp)
{
    return soc_ref_software_mmu_guest;
}

static void soc_ref_set_software_mmu_guest(Object *obj, bool value,
                                            Error **errp)
{
    soc_ref_software_mmu_guest = value;
}

static bool soc_ref_get_software_mmu_bootrom_guest(Object *obj, Error **errp)
{
    return soc_ref_software_mmu_bootrom_guest;
}

static void soc_ref_set_software_mmu_bootrom_guest(Object *obj, bool value,
                                                    Error **errp)
{
    soc_ref_software_mmu_bootrom_guest = value;
}

static target_ulong soc_ref_write_linux_rng_env(void)
{
    uint8_t env[12 + 1024 + 16] = { 0 };
    size_t first_len;
    size_t second_offset;
    size_t env_size;
    const char *seed = soc_ref_linux_rng_seed;
    const target_ulong env_virtual =
        cpu_mips_phys_to_kseg0(NULL, SOC_LINUX_RNG_ENV_BASE);

    if (!seed || !*seed) {
        stl_le_p(env, 0);
        env_size = sizeof(uint32_t);
    } else {
        first_len = strlen("rngseed=") + strlen(seed) + 1;
        second_offset = 12 + first_len;
        memcpy(env + 12, "rngseed=", strlen("rngseed="));
        memcpy(env + 12 + strlen("rngseed="), seed, strlen(seed));
        env[12 + first_len - 1] = '\0';
        memcpy(env + second_offset, "rngdet=1", strlen("rngdet=1") + 1);
        stl_le_p(env, env_virtual + 12);
        stl_le_p(env + 4, env_virtual + second_offset);
        stl_le_p(env + 8, 0);
        env_size = second_offset + strlen("rngdet=1") + 1;
    }

    if (address_space_write(&address_space_memory, SOC_LINUX_RNG_ENV_BASE,
                            MEMTXATTRS_UNSPECIFIED, env, env_size) != MEMTX_OK) {
        error_report("could not place Linux UHI RNG environment at 0x%" HWADDR_PRIx,
                     SOC_LINUX_RNG_ENV_BASE);
        exit(EXIT_FAILURE);
    }
    return env_virtual;
}

static void soc_ref_load_irq_schedule(MIPS32SocRefState *s)
{
    g_autofree gchar *contents = NULL;
    g_auto(GStrv) lines = NULL;
    gsize length = 0;

    if (!soc_ref_irq_schedule || !*soc_ref_irq_schedule) {
        return;
    }
    soc_ref_irq_replay_debug =
        g_strcmp0(g_getenv("QEMU_TRACE_IRQ_REPLAY"), "1") == 0;
    if (soc_ref_irq_replay_debug) {
        const char *context_index = g_getenv("QEMU_TRACE_IRQ_CONTEXT_INDEX");
        const char *context_window = g_getenv("QEMU_TRACE_IRQ_CONTEXT_WINDOW");
        if (context_index && *context_index) {
            gint64 parsed = g_ascii_strtoll(context_index, NULL, 0);
            if (parsed >= 0 && parsed <= G_MAXINT)
                soc_ref_irq_trace_context_index = parsed;
        }
        if (context_window && *context_window) {
            guint64 parsed = g_ascii_strtoull(context_window, NULL, 0);
            if (parsed <= 4096)
                soc_ref_irq_trace_context_window = parsed;
        }
    }
    if (!g_file_get_contents(soc_ref_irq_schedule, &contents, &length, NULL)) {
        error_report("could not load IRQ schedule '%s'", soc_ref_irq_schedule);
        exit(EXIT_FAILURE);
    }
    s->irq_release_after = g_array_new(false, false, sizeof(uint64_t));
    s->irq_replay_causes = g_array_new(false, false, sizeof(uint32_t));
    s->irq_replay_typed = g_array_new(false, false, sizeof(bool));
    s->irq_replay_epcs = g_array_new(false, false, sizeof(uint32_t));
    s->irq_replay_epc_valid = g_array_new(false, false, sizeof(bool));
    lines = g_strsplit(contents, "\n", -1);
    for (guint i = 0; lines[i]; ++i) {
        g_auto(GStrv) fields = NULL;
        const gchar *tokens[3] = { NULL, NULL, NULL };
        guint token_count = 0;
        gchar *end = NULL;
        guint64 value;
        guint64 epc_value = 0;
        guint64 cause_value = 1U << (8 + 2); /* Legacy schedules replay IP2. */
        uint32_t cause;
        uint32_t epc;
        uint32_t ip_mask;
        gboolean timer;
        bool typed;
        bool epc_valid = false;
        gchar *line = g_strstrip(lines[i]);

        if (!*line || line[0] == '#') {
            continue;
        }
        fields = g_strsplit_set(line, " \t\r", -1);
        for (guint j = 0; fields[j]; ++j) {
            if (*fields[j]) {
                if (token_count == G_N_ELEMENTS(tokens)) {
                    error_report("invalid IRQ schedule entry '%s'", line);
                    exit(EXIT_FAILURE);
                }
                tokens[token_count++] = fields[j];
            }
        }
        if (token_count >= 2) {
            typed = true;
            cause_value = g_ascii_strtoull(tokens[1], &end, 16);
            if (!end || *end || cause_value > UINT32_MAX) {
                error_report("invalid IRQ cause in schedule entry '%s'", line);
                exit(EXIT_FAILURE);
            }
        } else {
            typed = false;
        }
        if (token_count == 3) {
            end = NULL;
            epc_value = g_ascii_strtoull(tokens[2], &end, 16);
            if (!end || *end || epc_value > UINT32_MAX || (epc_value & 3)) {
                error_report("invalid IRQ EPC in schedule entry '%s'", line);
                exit(EXIT_FAILURE);
            }
            epc_valid = true;
        }
        end = NULL;
        value = token_count ? g_ascii_strtoull(tokens[0], &end, 10) : 0;
        cause = (uint32_t)cause_value;
        epc = (uint32_t)epc_value;
        ip_mask = (cause >> 8) & 0xffU;
        timer = (cause & (1U << CP0Ca_TI)) != 0;
        if (token_count == 0 || token_count > 3 || !end || *end || value == 0 ||
            (ip_mask & ~0x84U) != 0 ||
            (timer && !(ip_mask & 0x80U)) ||
            (!timer && !(ip_mask & 0x04U)) ||
            (s->irq_release_after->len &&
             value <= g_array_index(s->irq_release_after, uint64_t,
                                    s->irq_release_after->len - 1))) {
            error_report("invalid IRQ schedule entry '%s'", line);
            exit(EXIT_FAILURE);
        }
        g_array_append_val(s->irq_release_after, value);
        g_array_append_val(s->irq_replay_causes, cause);
        g_array_append_val(s->irq_replay_typed, typed);
        g_array_append_val(s->irq_replay_epcs, epc);
        g_array_append_val(s->irq_replay_epc_valid, epc_valid);
        s->irq_replay_has_timer |= timer;
    }
    if (!s->irq_release_after->len) {
        error_report("IRQ schedule '%s' has no release entries",
                     soc_ref_irq_schedule);
        exit(EXIT_FAILURE);
    }
    s->irq_replay_enabled = true;
}

static void soc_ref_load_cp0_count_schedule(MIPS32SocRefState *s)
{
    g_autofree gchar *contents = NULL;
    g_auto(GStrv) lines = NULL;
    gsize length = 0;

    if (!soc_ref_cp0_count_schedule_path ||
        !*soc_ref_cp0_count_schedule_path) {
        return;
    }
    if (!g_file_get_contents(soc_ref_cp0_count_schedule_path, &contents,
                             &length, NULL)) {
        error_report("could not load CP0 Count schedule '%s'",
                     soc_ref_cp0_count_schedule_path);
        exit(EXIT_FAILURE);
    }
    s->cp0_count_schedule = g_array_new(false, false,
                                        sizeof(MIPS32SocRefCountSample));
    lines = g_strsplit(contents, "\n", -1);
    for (guint i = 0; lines[i]; ++i) {
        g_auto(GStrv) fields = NULL;
        const gchar *tokens[5] = { NULL, NULL, NULL, NULL, NULL };
        guint token_count = 0;
        guint first = 0;
        gchar *end = NULL;
        guint64 pc, operand, value, retire_seq = 0;
        MIPS32SocRefCountSample sample;
        gchar *line = g_strstrip(lines[i]);

        if (!*line || line[0] == '#') {
            continue;
        }
        fields = g_strsplit_set(line, " \t\r", -1);
        for (guint j = 0; fields[j]; ++j) {
            if (*fields[j]) {
                if (token_count == G_N_ELEMENTS(tokens)) {
                    error_report("invalid CP0 Count schedule entry '%s'", line);
                    exit(EXIT_FAILURE);
                }
                tokens[token_count++] = fields[j];
            }
        }
        sample.is_rdhwr = token_count == 5 &&
            g_str_equal(tokens[0], "rdhwr");
        bool typed_mfc0 = token_count == 5 &&
            g_str_equal(tokens[0], "mfc0");
        if (sample.is_rdhwr || typed_mfc0) {
            first = 1;
        } else if (token_count != 3 && token_count != 4) {
            error_report("invalid CP0 Count schedule entry '%s'", line);
            exit(EXIT_FAILURE);
        }
        pc = g_ascii_strtoull(tokens[first], &end, 16);
        if (!end || *end || pc > UINT32_MAX) {
            error_report("invalid CP0 Count schedule PC in '%s'", line);
            exit(EXIT_FAILURE);
        }
        end = NULL;
        operand = g_ascii_strtoull(tokens[first + 1], &end, 10);
        if (!end || *end || operand > 31) {
            error_report("invalid CP0 Count schedule register in '%s'", line);
            exit(EXIT_FAILURE);
        }
        end = NULL;
        value = g_ascii_strtoull(tokens[first + 2], &end, 16);
        if (!end || *end || value > UINT32_MAX) {
            error_report("invalid CP0 Count schedule value in '%s'", line);
            exit(EXIT_FAILURE);
        }
        if ((sample.is_rdhwr && operand != 2) ||
            ((sample.is_rdhwr || typed_mfc0) && token_count != 5)) {
            error_report("invalid typed CP0 Count schedule entry '%s'", line);
            exit(EXIT_FAILURE);
        }
        if (token_count == 4 || token_count == 5) {
            end = NULL;
            retire_seq = g_ascii_strtoull(tokens[first + 3], &end, 10);
            if (!end || *end || !retire_seq) {
                error_report("invalid CP0 Count schedule retire sequence in '%s'",
                             line);
                exit(EXIT_FAILURE);
            }
        }
        sample.pc = (uint32_t)pc;
        sample.operand = (uint32_t)operand;
        sample.value = (uint32_t)value;
        sample.retire_seq = retire_seq;
        sample.has_retire_seq = token_count == 4 || token_count == 5;
        g_array_append_val(s->cp0_count_schedule, sample);
    }
    if (!s->cp0_count_schedule->len) {
        error_report("CP0 Count schedule '%s' has no samples",
                     soc_ref_cp0_count_schedule_path);
        exit(EXIT_FAILURE);
    }
}

static void soc_ref_load_cp0_random_schedule(MIPS32SocRefState *s)
{
    g_autofree gchar *contents = NULL;
    gsize length = 0;

    if (!soc_ref_cp0_random_schedule_path ||
        !*soc_ref_cp0_random_schedule_path) {
        return;
    }
    if (!g_file_get_contents(soc_ref_cp0_random_schedule_path, &contents,
                             &length, NULL)) {
        error_report("could not load CP0 Random schedule '%s'",
                     soc_ref_cp0_random_schedule_path);
        exit(EXIT_FAILURE);
    }
    if (length > (gsize)G_MAXUINT * 32U) {
        error_report("CP0 Random schedule '%s' exceeds the supported size",
                     soc_ref_cp0_random_schedule_path);
        exit(EXIT_FAILURE);
    }
    s->cp0_random_schedule = g_array_sized_new(
        false, false, sizeof(MIPS32SocRefRandomSample),
        (guint)(length / 32U + 1U));
    g_auto(GStrv) lines = g_strsplit(contents, "\n", -1);
    for (guint i = 0; lines[i]; ++i) {
        g_auto(GStrv) fields = NULL;
        const gchar *tokens[4] = { NULL, NULL, NULL, NULL };
        guint token_count = 0;
        gchar *end = NULL;
        guint64 retire_seq, pc, value;
        MIPS32SocRefRandomSample sample;
        gchar *line = g_strstrip(lines[i]);

        if (!*line || line[0] == '#') {
            continue;
        }
        fields = g_strsplit_set(line, " \t\r", -1);
        for (guint j = 0; fields[j]; ++j) {
            if (*fields[j]) {
                if (token_count == G_N_ELEMENTS(tokens)) {
                    error_report("invalid CP0 Random schedule entry '%s'",
                                 line);
                    exit(EXIT_FAILURE);
                }
                tokens[token_count++] = fields[j];
            }
        }
        if (token_count != G_N_ELEMENTS(tokens) ||
            (!g_str_equal(tokens[1], "mfc0") &&
             !g_str_equal(tokens[1], "tlbwr"))) {
            error_report("invalid CP0 Random schedule entry '%s'", line);
            exit(EXIT_FAILURE);
        }
        errno = 0;
        retire_seq = g_ascii_strtoull(tokens[0], &end, 10);
        if (errno == ERANGE || end == tokens[0] || !end || *end) {
            error_report("invalid CP0 Random schedule sequence in '%s'", line);
            exit(EXIT_FAILURE);
        }
        errno = 0;
        end = NULL;
        pc = g_ascii_strtoull(tokens[2], &end, 16);
        if (errno == ERANGE || end == tokens[2] || !end || *end ||
            pc > UINT32_MAX || (pc & 3U)) {
            error_report("invalid CP0 Random schedule PC in '%s'", line);
            exit(EXIT_FAILURE);
        }
        errno = 0;
        end = NULL;
        value = g_ascii_strtoull(tokens[3], &end, 16);
        if (errno == ERANGE || end == tokens[3] || !end || *end ||
            value >= 64U) {
            error_report("invalid CP0 Random schedule value in '%s'", line);
            exit(EXIT_FAILURE);
        }
        if (s->cp0_random_schedule->len) {
            MIPS32SocRefRandomSample previous =
                g_array_index(s->cp0_random_schedule,
                              MIPS32SocRefRandomSample,
                              s->cp0_random_schedule->len - 1);
            if (retire_seq <= previous.retire_seq) {
                error_report("non-monotonic CP0 Random schedule entry '%s'",
                             line);
                exit(EXIT_FAILURE);
            }
        }
        sample.retire_seq = retire_seq;
        sample.pc = (uint32_t)pc;
        sample.value = (uint32_t)value;
        sample.is_tlbwr = g_str_equal(tokens[1], "tlbwr");
        g_array_append_val(s->cp0_random_schedule, sample);
    }
    if (!s->cp0_random_schedule->len) {
        error_report("CP0 Random schedule '%s' has no events",
                     soc_ref_cp0_random_schedule_path);
        exit(EXIT_FAILURE);
    }
}

static void soc_ref_load_cpu_cycle_schedule(MIPS32SocRefState *s)
{
    g_autofree gchar *contents = NULL;
    gsize length = 0;

    if (!soc_ref_cpu_cycle_schedule_path ||
        !*soc_ref_cpu_cycle_schedule_path) {
        return;
    }
    if (!g_file_get_contents(soc_ref_cpu_cycle_schedule_path, &contents,
                             &length, NULL)) {
        error_report("could not load CPU cycle schedule '%s'",
                     soc_ref_cpu_cycle_schedule_path);
        exit(EXIT_FAILURE);
    }
    if (length > (gsize)G_MAXUINT * 16U) {
        error_report("CPU cycle schedule '%s' exceeds the supported size",
                     soc_ref_cpu_cycle_schedule_path);
        exit(EXIT_FAILURE);
    }
    s->cpu_cycle_schedule = g_array_sized_new(
        false, false, sizeof(MIPS32SocRefCpuCycleSample),
        (guint)(length / 16U + 1U));
    gchar *line = contents;
    gchar *contents_end = contents + length;
    while (line < contents_end) {
        gchar *line_end = memchr(line, '\n', contents_end - line);
        gchar *next_line = line_end ? line_end + 1 : contents_end;
        gchar *cursor;
        gchar *end = NULL;
        guint64 retire_seq, cycle;
        MIPS32SocRefCpuCycleSample sample;

        if (line_end) {
            *line_end = '\0';
        }
        line = g_strstrip(line);

        if (!*line || line[0] == '#') {
            line = next_line;
            continue;
        }
        cursor = line;
        if (!g_ascii_isdigit(*cursor)) {
            error_report("invalid CPU cycle schedule entry '%s'", line);
            exit(EXIT_FAILURE);
        }
        errno = 0;
        retire_seq = g_ascii_strtoull(cursor, &end, 10);
        if (errno == ERANGE || end == cursor || !end) {
            error_report("invalid CPU cycle schedule retire sequence in '%s'",
                         line);
            exit(EXIT_FAILURE);
        }
        cursor = end;
        while (g_ascii_isspace(*cursor)) {
            ++cursor;
        }
        if (!g_ascii_isdigit(*cursor)) {
            error_report("invalid CPU cycle schedule entry '%s'", line);
            exit(EXIT_FAILURE);
        }
        errno = 0;
        cycle = g_ascii_strtoull(cursor, &end, 10);
        if (errno == ERANGE || end == cursor || !end) {
            error_report("invalid CPU cycle schedule cycle in '%s'", line);
            exit(EXIT_FAILURE);
        }
        cursor = end;
        while (g_ascii_isspace(*cursor)) {
            ++cursor;
        }
        if (*cursor) {
            error_report("invalid CPU cycle schedule entry '%s'", line);
            exit(EXIT_FAILURE);
        }
        if (s->cpu_cycle_schedule->len) {
            MIPS32SocRefCpuCycleSample previous =
                g_array_index(s->cpu_cycle_schedule,
                              MIPS32SocRefCpuCycleSample,
                              s->cpu_cycle_schedule->len - 1);
            if (retire_seq <= previous.retire_seq || cycle < previous.cycle) {
                error_report("non-monotonic CPU cycle schedule entry '%s'",
                             line);
                exit(EXIT_FAILURE);
            }
        } else if (retire_seq != 0) {
            error_report("CPU cycle schedule must start at retire sequence 0");
            exit(EXIT_FAILURE);
        }
        sample.retire_seq = retire_seq;
        sample.cycle = cycle;
        g_array_append_val(s->cpu_cycle_schedule, sample);
        line = next_line;
    }
    if (s->cpu_cycle_schedule->len < 2) {
        error_report("CPU cycle schedule '%s' needs at least two samples",
                     soc_ref_cpu_cycle_schedule_path);
        exit(EXIT_FAILURE);
    }
}

static void soc_ref_load_uart_apb_schedule(MIPS32SocRefState *s)
{
    g_autofree gchar *contents = NULL;
    gsize length = 0;

    if (!soc_ref_uart_apb_schedule_path ||
        !*soc_ref_uart_apb_schedule_path) {
        return;
    }
    if (!g_file_get_contents(soc_ref_uart_apb_schedule_path, &contents,
                             &length, NULL)) {
        error_report("could not load UART APB schedule '%s'",
                     soc_ref_uart_apb_schedule_path);
        exit(EXIT_FAILURE);
    }
    s->uart_apb_schedule = g_array_new(false, false,
                                       sizeof(MIPS32SocRefUartApbSample));
    gchar *line = contents;
    gchar *contents_end = contents + length;
    while (line < contents_end) {
        gchar *line_end = memchr(line, '\n', contents_end - line);
        gchar *next_line = line_end ? line_end + 1 : contents_end;
        g_auto(GStrv) fields = NULL;
        const gchar *tokens[4] = { NULL, NULL, NULL, NULL };
        guint token_count = 0;
        gchar *end = NULL;
        guint64 cycle, write, address, data;
        MIPS32SocRefUartApbSample sample;

        if (line_end) {
            *line_end = '\0';
        }
        line = g_strstrip(line);
        if (!*line || line[0] == '#') {
            line = next_line;
            continue;
        }
        fields = g_strsplit_set(line, " \t\r", -1);
        for (guint i = 0; fields[i]; ++i) {
            if (*fields[i]) {
                if (token_count == G_N_ELEMENTS(tokens)) {
                    error_report("invalid UART APB schedule entry '%s'", line);
                    exit(EXIT_FAILURE);
                }
                tokens[token_count++] = fields[i];
            }
        }
        if (token_count != G_N_ELEMENTS(tokens)) {
            error_report("invalid UART APB schedule entry '%s'", line);
            exit(EXIT_FAILURE);
        }
        errno = 0;
        cycle = g_ascii_strtoull(tokens[0], &end, 10);
        if (errno == ERANGE || end == tokens[0] || !end || *end) {
            error_report("invalid UART APB schedule cycle in '%s'", line);
            exit(EXIT_FAILURE);
        }
        errno = 0;
        end = NULL;
        write = g_ascii_strtoull(tokens[1], &end, 10);
        if (errno == ERANGE || end == tokens[1] || !end || *end || write > 1) {
            error_report("invalid UART APB schedule direction in '%s'", line);
            exit(EXIT_FAILURE);
        }
        errno = 0;
        end = NULL;
        address = g_ascii_strtoull(tokens[2], &end, 16);
        if (errno == ERANGE || end == tokens[2] || !end || *end ||
            address < SOC_UART_APB_BASE ||
            address > SOC_UART_APB_BASE + (7U << 2) || (address & 3U)) {
            error_report("invalid UART APB schedule address in '%s'", line);
            exit(EXIT_FAILURE);
        }
        errno = 0;
        end = NULL;
        data = g_ascii_strtoull(tokens[3], &end, 16);
        if (errno == ERANGE || end == tokens[3] || !end || *end ||
            data > UINT32_MAX) {
            error_report("invalid UART APB schedule data in '%s'", line);
            exit(EXIT_FAILURE);
        }
        if (s->uart_apb_schedule->len) {
            MIPS32SocRefUartApbSample previous =
                g_array_index(s->uart_apb_schedule,
                              MIPS32SocRefUartApbSample,
                              s->uart_apb_schedule->len - 1);
            if (cycle < previous.cycle) {
                error_report("non-monotonic UART APB schedule entry '%s'",
                             line);
                exit(EXIT_FAILURE);
            }
        }
        sample.cycle = cycle;
        sample.write = write != 0;
        sample.address = (uint32_t)address;
        sample.data = (uint32_t)data;
        g_array_append_val(s->uart_apb_schedule, sample);
        line = next_line;
    }
    if (!s->uart_apb_schedule->len) {
        error_report("UART APB schedule '%s' has no events",
                     soc_ref_uart_apb_schedule_path);
        exit(EXIT_FAILURE);
    }
}

static void soc_ref_report_cp0_count_schedule(void)
{
    MIPS32SocRefState *s = soc_ref_active_state;

    if (s && s->cp0_count_schedule) {
        fprintf(stderr,
                "SOC_REF_CP0_COUNT_SCHEDULE consumed=%u total=%u\n",
                s->cp0_count_schedule_index, s->cp0_count_schedule->len);
        fflush(stderr);
        fprintf(stderr,
                "SOC_REF_CP0_COUNT_SCHEDULE_SEQ_RESYNC count=%" PRIu64
                " max_lag=%" PRIu64 "\n",
                s->cp0_count_schedule_seq_resyncs,
                s->cp0_count_schedule_max_seq_lag);
        fflush(stderr);
    }
}

static void soc_ref_report_cp0_random_schedule(void)
{
    MIPS32SocRefState *s = soc_ref_active_state;

    if (s && s->cp0_random_schedule) {
        fprintf(stderr,
                "SOC_REF_CP0_RANDOM_SCHEDULE consumed=%u total=%u\n",
                s->cp0_random_schedule_index,
                s->cp0_random_schedule->len);
        fflush(stderr);
    }
}

static void soc_ref_report_cpu_cycle_schedule(void)
{
    MIPS32SocRefState *s = soc_ref_active_state;

    if (s && s->cpu_cycle_schedule) {
        MIPS32SocRefCpuCycleSample final_sample =
            g_array_index(s->cpu_cycle_schedule,
                          MIPS32SocRefCpuCycleSample,
                          s->cpu_cycle_schedule->len - 1);
        fprintf(stderr,
                "SOC_REF_CPU_CYCLE_SCHEDULE used_through=%" PRIu64
                " total=%u final_seq=%" PRIu64 "\n",
                s->cpu_cycle_schedule_used_through,
                s->cpu_cycle_schedule->len, final_sample.retire_seq);
        fflush(stderr);
    }
}

static void soc_ref_report_uart_apb_schedule(void)
{
    MIPS32SocRefState *s = soc_ref_active_state;

    if (s && s->uart_apb_schedule) {
        fprintf(stderr,
                "SOC_REF_UART_APB_SCHEDULE consumed=%u total=%u\n",
                s->uart_apb_schedule_index, s->uart_apb_schedule->len);
        fflush(stderr);
    }
}

static void soc_ref_report_irq_schedule(void)
{
    MIPS32SocRefState *s = soc_ref_active_state;

    if (s && s->irq_release_after) {
        fprintf(stderr, "SOC_REF_IRQ_SCHEDULE released=%u total=%u\n",
                s->irq_release_index, s->irq_release_after->len);
        fflush(stderr);
    }
}

static uint64_t soc_ref_mailbox_read(void *opaque, hwaddr addr,
                                     unsigned size)
{
    MIPS32SocRefState *s = opaque;
    uint8_t *ram;

    if (!s->sram || addr + size > SOC_SRAM_SIZE || size != sizeof(uint32_t))
        return 0;
    ram = memory_region_get_ram_ptr(s->sram);
    return ldl_le_p(ram + addr);
}

static void soc_ref_mailbox_write(void *opaque, hwaddr addr, uint64_t data,
                                  unsigned size)
{
    MIPS32SocRefState *s = opaque;
    if (size == sizeof(uint32_t) && (uint32_t)data == SOC_MAILBOX_MAGIC) {
        qemu_system_shutdown_request_with_code(SHUTDOWN_CAUSE_GUEST_SHUTDOWN,
                                               0);
        return;
    }
    /* RTL decodes the mailbox by virtual address.  Its physical SRAM word at
     * 0xfffc remains usable by the stack, so non-magic accesses must fall
     * through to the underlying RAM rather than being swallowed by QEMU's
     * physical mailbox overlay. */
    if (s->sram && size == sizeof(uint32_t) && addr + size <= SOC_SRAM_SIZE) {
        uint8_t *ram = memory_region_get_ram_ptr(s->sram);
        stl_le_p(ram + addr, (uint32_t)data);
    }
}

static const MemoryRegionOps soc_ref_mailbox_ops = {
    .read = soc_ref_mailbox_read,
    .write = soc_ref_mailbox_write,
    .endianness = DEVICE_LITTLE_ENDIAN,
    .valid = {
        .min_access_size = 4,
        .max_access_size = 4,
    },
};

static uint32_t soc_ref_uart_count_ticks(MIPS32SocRefState *s)
{
    if (s->cp0_retire_clock && s->cpu) {
        return qemu_mips32_soc_ref_cp0_retire_ticks(&s->cpu->env);
    }
    return (uint32_t)s->retire_count;
}

static uint64_t soc_ref_uart_cycle_at_retire(MIPS32SocRefState *s,
                                             uint64_t retire_seq)
{
    if (s->cpu_cycle_schedule && s->cp0_retire_clock && s->cpu) {
        size_t cursor = s->cpu_cycle_schedule_index;
        uint64_t cycle = soc_ref_cpu_cycle_at_retire(
            (const SocRefCpuCycleSample *)s->cpu_cycle_schedule->data,
            s->cpu_cycle_schedule->len, retire_seq, &cursor);

        s->cpu_cycle_schedule_index = cursor;
        if (retire_seq > s->cpu_cycle_schedule_used_through) {
            s->cpu_cycle_schedule_used_through = retire_seq;
        }
        return cycle;
    }
    return (uint64_t)soc_ref_uart_count_ticks(s) * 2U;
}

static uint64_t soc_ref_uart_clock_cycles(MIPS32SocRefState *s)
{
    return soc_ref_uart_cycle_at_retire(s, s->cpu_cycle_retire_seq + 1);
}

static uint16_t soc_ref_uart_current_divisor(MIPS32SocRefState *s)
{
    return (uint16_t)s->uart_dll | ((uint16_t)s->uart_dlm << 8);
}

static void soc_ref_uart_advance_before_cycle(MIPS32SocRefState *s,
                                             uint64_t cycle)
{
    soc_ref_uart_tx_advance_before(
        &s->uart_tx, cycle, (uint8_t)s->uart_regs[3],
        soc_ref_uart_current_divisor(s), (uint8_t)s->uart_regs[2],
        (uint8_t)s->uart_regs[4], false);
}

static void soc_ref_uart_advance_through_cycle(MIPS32SocRefState *s,
                                               uint64_t cycle)
{
    soc_ref_uart_tx_advance_through(
        &s->uart_tx, cycle, (uint8_t)s->uart_regs[3],
        soc_ref_uart_current_divisor(s), (uint8_t)s->uart_regs[2],
        (uint8_t)s->uart_regs[4], false);
}

static bool soc_ref_uart_step_cycle(MIPS32SocRefState *s, uint64_t cycle,
                                    bool write_thr, uint8_t thr_data,
                                    bool clear_fifo)
{
    return soc_ref_uart_tx_step(
        &s->uart_tx, cycle, (uint8_t)s->uart_regs[3],
        soc_ref_uart_current_divisor(s), (uint8_t)s->uart_regs[2],
        (uint8_t)s->uart_regs[4], false, write_thr, thr_data, clear_fifo);
}

static void soc_ref_uart_update_irq(MIPS32SocRefState *s);

static bool soc_ref_uart_take_apb_sample(MIPS32SocRefState *s,
                                        uint32_t address, bool write,
                                        uint32_t data,
                                        MIPS32SocRefUartApbSample *sample)
{
    MIPS32SocRefUartApbSample expected;

    if (!s->uart_apb_schedule ||
        s->uart_apb_schedule_diagnostic_bypassed) {
        return false;
    }
    /* Shutdown is asynchronous after the terminal UART marker. */
    if (s->terminal_marker_seen) {
        return false;
    }
    if (s->uart_apb_schedule_index >= s->uart_apb_schedule->len) {
        error_report("UART APB schedule exhausted at retire=%" PRIu64
                     " access=%c%08" PRIx32,
                     s->retire_count, write ? 'W' : 'R', address);
        exit(EXIT_FAILURE);
    }
    expected = g_array_index(s->uart_apb_schedule,
                             MIPS32SocRefUartApbSample,
                             s->uart_apb_schedule_index);
    if (expected.address != address || expected.write != write ||
        (write && expected.data != data)) {
        uint64_t qemu_cycle = soc_ref_uart_clock_cycles(s);
        uint64_t qemu_pc = s->cpu ? s->cpu->env.active_tc.PC : 0;

        error_report("UART APB schedule mismatch index=%u retire=%" PRIu64
                     " expected=%c%08" PRIx32 "/%08" PRIx32
                     " qemu=%c%08" PRIx32 "/%08" PRIx32
                     " pc=%08" PRIx64 " cycle=%" PRIu64
                     " expected_cycle=%" PRIu64 " diagnostic_continue=%u",
                     s->uart_apb_schedule_index, s->retire_count,
                     expected.write ? 'W' : 'R', expected.address,
                     expected.data, write ? 'W' : 'R', address, data,
                     qemu_pc, qemu_cycle,
                     expected.cycle,
                     soc_ref_uart_apb_schedule_diagnostic_continue);
        if (s->cpu) {
            CPUMIPSState *env = &s->cpu->env;
            error_report("UART APB mismatch context ra=%08" PRIx64
                         " t9=%08" PRIx64 " v0=%08" PRIx64
                         " a0=%08" PRIx64 " a1=%08" PRIx64
                         " a2=%08" PRIx64 " a3=%08" PRIx64
                         " status=%08" PRIx32 " cause=%08" PRIx32
                         " retire_seq=%" PRIu64
                         " ier=%02" PRIx32 " fcr=%02" PRIx32
                         " lcr=%02" PRIx32 " mcr=%02" PRIx32
                         " tx_pending=%zu tx_active=%u writes=%" PRIu64,
                         (uint64_t)env->active_tc.gpr[31],
                         (uint64_t)env->active_tc.gpr[25],
                         (uint64_t)env->active_tc.gpr[2],
                         (uint64_t)env->active_tc.gpr[4],
                         (uint64_t)env->active_tc.gpr[5],
                         (uint64_t)env->active_tc.gpr[6],
                         (uint64_t)env->active_tc.gpr[7],
                         env->CP0_Status, env->CP0_Cause,
                         s->cpu_cycle_retire_seq,
                         s->uart_regs[1], s->uart_regs[2],
                         s->uart_regs[3], s->uart_regs[4],
                         s->uart_tx.pending_count, s->uart_tx.active,
                         s->uart_write_count);
        }
        if (!soc_ref_uart_apb_schedule_diagnostic_continue) {
            exit(EXIT_FAILURE);
        }
        /* Diagnostic mode lets the retire comparator expose the architectural
         * mismatch after the APB schedule stops being applicable. */
        s->uart_apb_schedule_diagnostic_bypassed = true;
        return false;
    }
    ++s->uart_apb_schedule_index;
    *sample = expected;
    return true;
}

static void soc_ref_uart_check_apb_read(MIPS32SocRefState *s,
                                        const MIPS32SocRefUartApbSample *sample,
                                        uint32_t value)
{
    if (s->uart_apb_schedule && sample->data != value) {
        error_report("UART APB read mismatch index=%u retire=%" PRIu64
                     " cycle=%" PRIu64 " address=%08" PRIx32
                     " rtl=%08" PRIx32 " qemu=%08" PRIx32,
                     s->uart_apb_schedule_index - 1, s->retire_count,
                     sample->cycle, sample->address, sample->data, value);
        exit(EXIT_FAILURE);
    }
}

static uint64_t soc_ref_uart_read(void *opaque, hwaddr addr, unsigned size)
{
    MIPS32SocRefState *s = opaque;
    unsigned reg = addr >> 2;
    MIPS32SocRefUartApbSample sample = {0};
    bool retire_timed = s->cp0_retire_clock && s->cpu;
    bool scheduled = soc_ref_uart_take_apb_sample(
        s, SOC_UART_APB_BASE + (reg << 2), false, 0, &sample);
    uint32_t value = 0;
    uint64_t now_cycle = 0;

    if (retire_timed) {
        now_cycle = scheduled ? sample.cycle :
                                soc_ref_uart_clock_cycles(s);
        soc_ref_uart_advance_before_cycle(s, now_cycle);
    }

    soc_ref_uart_modem_update(&s->uart_modem, s->uart_regs[4]);

    if (reg == 0 && (s->uart_regs[3] & 0x80U)) {
        value = s->uart_dll;
    } else if (reg == 1 && (s->uart_regs[3] & 0x80U)) {
        value = s->uart_dlm;
    } else if (reg == 2) {
        value = soc_ref_uart_iir_status(&s->uart_tx, s->uart_regs[1],
                                        s->uart_regs[2]);
    } else if (reg == 5) {
        if (s->uart_diff_timing) {
            /* The nonblocking Linux differential deliberately removes
             * cache-dependent TX drain timing from the polling contract. */
            value = SOC_REF_UART_LSR_TEMT;
        } else if (retire_timed) {
            value = soc_ref_uart_tx_lsr_status(&s->uart_tx);
        } else {
            if (s->uart_tx_busy_reads) {
                --s->uart_tx_busy_reads;
                value = SOC_REF_UART_LSR_THRE;
            } else {
                value = SOC_REF_UART_LSR_TEMT;
            }
        }
        if (s->peripheral_trace) {
            fprintf(s->peripheral_trace,
                    "{\"kind\":\"uart\",\"addr\":\"0x%08" PRIx64
                    "\",\"data\":\"0x%02x\",\"write\":false"
                    ",\"width\":%u,\"retire\":%" PRIu64,
                    (uint64_t)(SOC_UART_BASE + 5 * 4), value, size,
                    s->retire_count);
            if (retire_timed) {
                fprintf(s->peripheral_trace,
                        ",\"cycle\":%" PRIu64
                        ",\"baud_count\":%u,\"tx_state\":%u"
                        ",\"pending\":%zu",
                        now_cycle, s->uart_tx.baud_count,
                        s->uart_tx.tx_state, s->uart_tx.pending_count);
            } else {
                fprintf(s->peripheral_trace, ",\"busy_reads\":%u",
                        s->uart_tx_busy_reads);
            }
            fputs("}\n", s->peripheral_trace);
            fflush(s->peripheral_trace);
        }
    } else if (reg == 6) {
        value = soc_ref_uart_modem_read(&s->uart_modem, s->uart_regs[4]);
    } else if (reg < ARRAY_SIZE(s->uart_regs)) {
        value = s->uart_regs[reg];
    }
    if (scheduled) {
        soc_ref_uart_check_apb_read(s, &sample, value);
    }
    if (retire_timed) {
        soc_ref_uart_step_cycle(s, now_cycle, false, 0, false);
        soc_ref_uart_update_irq(s);
    }
    return value;
}

/* Legacy non-retire-clock gates lack the normalized CPU timebase used by the
 * Linux differential, so retain their deterministic poll-count behavior. */
static unsigned soc_ref_uart_profile_busy_reads(uint64_t ordinal, uint8_t ch)
{
    static const struct {
        uint16_t ordinal;
        uint8_t busy_reads;
    } line_start_profile[] = {
        { 1, 2 }, { 179, 3 }, { 234, 3 }, { 289, 3 }, { 358, 3 },
        { 393, 3 }, { 413, 2 }, { 474, 2 }, { 537, 1 }, { 597, 2 },
        { 676, 2 }, { 759, 1 }, { 788, 2 }, { 814, 3 }, { 859, 2 },
        { 892, 2 }, { 941, 2 }, { 982, 2 }, { 1009, 3 }, { 1054, 2 },
        { 1090, 3 }, { 1135, 1 }, { 1174, 1 }, { 1247, 1 }, { 1446, 1 },
        { 1532, 1 }, { 1616, 2 }, { 1665, 2 }, { 1715, 2 }, { 1791, 2 },
        { 1869, 1 }, { 2032, 1 }, { 2108, 2 }, { 2162, 2 }, { 2214, 2 },
        { 2290, 2 }, { 2345, 2 }, { 2432, 2 }, { 2509, 1 }, { 2538, 1 },
        { 2609, 2 }, { 2688, 2 }, { 2742, 2 }, { 2846, 2 }, { 2936, 1 },
        { 2987, 2 }, { 3080, 2 }, { 3133, 2 }, { 3217, 1 }, { 3306, 2 },
        { 3393, 1 }, { 3448, 2 }, { 3508, 2 }, { 3560, 2 },
        { 3606, 1 }, { 3644, 1 },
    };
    size_t i;

    if (ch != '[')
        return 3;
    for (i = 0; i < ARRAY_SIZE(line_start_profile); ++i) {
        if (line_start_profile[i].ordinal == ordinal)
            return line_start_profile[i].busy_reads;
    }
    /* Two busy reads is the modal line-start phase in the Linux profile. */
    return 2;
}

static void soc_ref_update_irq(MIPS32SocRefState *s);

/* In retire-clock mode the synthetic Count has no host timer deadline.  The
 * guest may therefore reach Compare while executing ordinary instructions or
 * WAIT without reading Count again.  Keep Cause.TI and the pending IRQ line
 * architectural; a captured IRQ schedule controls CPU acceptance. */
static void soc_ref_cp0_retire_timer_tick(MIPS32SocRefState *s)
{
    CPUMIPSState *env;
    uint32_t count;
    bool replay_pending;

    if (!s || !s->cp0_retire_clock || !s->cpu ||
        !qemu_mips32_soc_ref_cp0_timer_armed()) {
        return;
    }
    env = &s->cpu->env;
    if (env->CP0_Cause & (1U << CP0Ca_TI)) {
        return;
    }
    replay_pending = soc_ref_timer_replay_pending(s);
    count = qemu_mips32_soc_ref_cp0_retire_ticks(env);
    /* Count replay samples are sparse; a retire tick can cross Compare
     * between samples.  Once crossed, TI remains pending until Compare is
     * written, matching the RTL latch semantics. */
    if (!replay_pending && (int32_t)(count - env->CP0_Compare) < 0) {
        return;
    }
    env->CP0_Cause |= 1U << CP0Ca_TI;
    soc_ref_assert_cp0_timer_irq(s);
}

static void soc_ref_uart_update_irq(MIPS32SocRefState *s)
{
    bool level = soc_ref_uart_tx_irq_pending(&s->uart_tx,
                                             s->uart_regs[1]);

    /* Match RTL: UART aggregate interrupt is VIC source 1, and the VIC
     * aggregate is routed to CPU Cause.IP2. Linux uses the same cascade. */
    if (level)
        s->pic_raw |= 1U << 1;
    else
        s->pic_raw &= ~(1U << 1);
    soc_ref_update_irq(s);
}

static void soc_ref_uart_retire_tick(MIPS32SocRefState *s)
{
    uint64_t now_cycle;

    if (!s || !s->cpu || !s->cp0_retire_clock ||
        !(s->uart_regs[1] & 0x2U)) {
        return;
    }
    /* The APB schedule validates accesses, but it does not replace the
     * retire-clock timeline.  Advance the shifter between accesses as well,
     * otherwise a frame that drains while the guest is touching another
     * peripheral never raises the level-sensitive TX IRQ. */
    now_cycle = soc_ref_uart_cycle_at_retire(s, s->cpu_cycle_retire_seq);
    soc_ref_uart_advance_through_cycle(s, now_cycle);
    soc_ref_uart_update_irq(s);
}

static bool soc_ref_uart_observe_terminal_marker(MIPS32SocRefState *s,
                                                 uint8_t byte)
{
    static const char marker[] = SOC_REF_LINUX_TERMINAL_MARKER;

    if (!s->stop_on_terminal_marker || s->terminal_marker_seen) {
        return false;
    }
    if (byte == '\r' &&
        s->terminal_marker_progress == sizeof(marker) - 2) {
        return false;
    }
    if (byte == (uint8_t)marker[s->terminal_marker_progress]) {
        ++s->terminal_marker_progress;
    } else if (byte == (uint8_t)marker[0]) {
        s->terminal_marker_progress = 1;
    } else {
        s->terminal_marker_progress = 0;
    }
    if (s->terminal_marker_progress != sizeof(marker) - 1) {
        return false;
    }
    s->terminal_marker_seen = true;
    return true;
}

static void soc_ref_uart_write(void *opaque, hwaddr addr, uint64_t data,
                               unsigned size)
{
    MIPS32SocRefState *s = opaque;
    unsigned reg = addr >> 2;
    MIPS32SocRefUartApbSample sample = {0};
    bool retire_timed = s->cp0_retire_clock && s->cpu;
    bool scheduled = soc_ref_uart_take_apb_sample(
        s, SOC_UART_APB_BASE + (reg << 2), true, (uint32_t)data, &sample);
    uint64_t now_cycle = 0;

    if (retire_timed) {
        now_cycle = scheduled ? sample.cycle :
                                soc_ref_uart_clock_cycles(s);
        soc_ref_uart_advance_before_cycle(s, now_cycle);
    }
    soc_ref_uart_modem_update(&s->uart_modem, s->uart_regs[4]);

    if (reg == 0) {
        if (s->uart_regs[3] & 0x80U) {
            if (retire_timed) {
                soc_ref_uart_step_cycle(s, now_cycle, false, 0, false);
            }
            s->uart_dll = data & 0xffU;
            return;
        }
        uint8_t ch = data & 0xff;
        bool accepted = true;
        ++s->uart_write_count;
        if (retire_timed) {
            accepted = soc_ref_uart_step_cycle(
                s, now_cycle, true, ch, false);
            s->uart_tx_busy_reads = 0;
        } else {
            s->uart_tx_busy_reads =
                soc_ref_uart_profile_busy_reads(s->uart_write_count, ch);
        }
        if (s->peripheral_trace) {
            fprintf(s->peripheral_trace,
                    "{\"kind\":\"uart\",\"addr\":\"0x%08" PRIx64
                    "\",\"data\":\"0x%02x\",\"write\":true,\"width\":1"
                    ",\"retire\":%" PRIu64 "}\n",
                    (uint64_t)SOC_UART_BASE, ch, s->retire_count);
            fflush(s->peripheral_trace);
        }
        if (accepted) {
            putchar(ch);
            fflush(stdout);
            if (soc_ref_uart_observe_terminal_marker(s, ch)) {
                qemu_system_shutdown_request(SHUTDOWN_CAUSE_GUEST_SHUTDOWN);
                /* End the active TCG block before it can perform another
                 * scheduled CP0 read while asynchronous shutdown is pending. */
                if (s->cpu) {
                    cpu_exit(CPU(s->cpu));
                }
            }
        }
        soc_ref_uart_update_irq(s);
        return;
    }
    if (reg == 1 && (s->uart_regs[3] & 0x80U)) {
        if (retire_timed) {
            soc_ref_uart_step_cycle(s, now_cycle, false, 0, false);
        }
        s->uart_dlm = data & 0xffU;
        return;
    }
    if (reg == 2) {
        uint8_t fcr = data & 0xffU;

        if (retire_timed) {
            soc_ref_uart_step_cycle(s, now_cycle, false, 0,
                                    (fcr & 0x04U) != 0);
        }
        s->uart_regs[2] = fcr & 0xc1U;
        soc_ref_uart_update_irq(s);
        return;
    }
    if (reg < ARRAY_SIZE(s->uart_regs)) {
        if (retire_timed) {
            soc_ref_uart_step_cycle(s, now_cycle, false, 0, false);
        }
        s->uart_regs[reg] = data;
        if (reg == 4) {
            soc_ref_uart_modem_update(&s->uart_modem,
                                     (uint8_t)s->uart_regs[4]);
        }
        soc_ref_uart_update_irq(s);
    }
}

static const MemoryRegionOps soc_ref_uart_ops = {
    .read = soc_ref_uart_read,
    .write = soc_ref_uart_write,
    .endianness = DEVICE_LITTLE_ENDIAN,
    .valid = {
        .min_access_size = 1,
        .max_access_size = 4,
    },
};

static uint64_t soc_ref_apb_read(void *opaque, hwaddr addr, unsigned size);
static void soc_ref_apb_write(void *opaque, hwaddr addr, uint64_t data,
                              unsigned size);

static uint64_t soc_ref_dma_legacy_read(void *opaque, hwaddr addr,
                                        unsigned size)
{
    return soc_ref_apb_read(opaque, addr + 0x3000, size);
}

static void soc_ref_dma_legacy_write(void *opaque, hwaddr addr,
                                     uint64_t data, unsigned size)
{
    soc_ref_apb_write(opaque, addr + 0x3000, data, size);
}

static const MemoryRegionOps soc_ref_dma_legacy_ops = {
    .read = soc_ref_dma_legacy_read,
    .write = soc_ref_dma_legacy_write,
    .endianness = DEVICE_LITTLE_ENDIAN,
    .valid = {
        .min_access_size = 4,
        .max_access_size = 4,
    },
};

static uint64_t soc_ref_dma_v2_read(void *opaque, hwaddr addr, unsigned size)
{
    return soc_ref_apb_read(opaque, addr + 0x3040, size);
}

static void soc_ref_dma_v2_write(void *opaque, hwaddr addr, uint64_t data,
                                 unsigned size)
{
    soc_ref_apb_write(opaque, addr + 0x3040, data, size);
}

static const MemoryRegionOps soc_ref_dma_v2_ops = {
    .read = soc_ref_dma_v2_read,
    .write = soc_ref_dma_v2_write,
    .endianness = DEVICE_LITTLE_ENDIAN,
    .valid = {
        .min_access_size = 4,
        .max_access_size = 4,
    },
};

static uint64_t soc_ref_pic_read(void *opaque, hwaddr addr, unsigned size)
{
    return soc_ref_apb_read(opaque, addr + 0x4000, size);
}

static void soc_ref_pic_write(void *opaque, hwaddr addr, uint64_t data,
                              unsigned size)
{
    soc_ref_apb_write(opaque, addr + 0x4000, data, size);
}

static const MemoryRegionOps soc_ref_pic_ops = {
    .read = soc_ref_pic_read,
    .write = soc_ref_pic_write,
    .endianness = DEVICE_LITTLE_ENDIAN,
    .valid = { .min_access_size = 4, .max_access_size = 4 },
};

static uint64_t soc_ref_ipi_read(void *opaque, hwaddr addr, unsigned size)
{
    unsigned bank = (uintptr_t)opaque;
    return soc_ref_apb_read(soc_ref_active_state, addr +
                            (bank ? 0xb000 : 0xa000), size);
}

static void soc_ref_ipi_write(void *opaque, hwaddr addr, uint64_t data,
                              unsigned size)
{
    unsigned bank = (uintptr_t)opaque;
    soc_ref_apb_write(soc_ref_active_state, addr +
                      (bank ? 0xb000 : 0xa000), data, size);
}

static const MemoryRegionOps soc_ref_ipi_ops = {
    .read = soc_ref_ipi_read,
    .write = soc_ref_ipi_write,
    .endianness = DEVICE_LITTLE_ENDIAN,
    .valid = { .min_access_size = 4, .max_access_size = 4 },
};

static uint64_t soc_ref_window_read(void *opaque, hwaddr addr, unsigned size,
                                    hwaddr base)
{
    return soc_ref_apb_read(opaque, addr + base, size);
}

static void soc_ref_window_write(void *opaque, hwaddr addr, uint64_t data,
                                 unsigned size, hwaddr base)
{
    soc_ref_apb_write(opaque, addr + base, data, size);
}

static uint64_t soc_ref_qspi_read(void *opaque, hwaddr addr, unsigned size)
{
    return soc_ref_window_read(opaque, addr, size, 0x5000);
}

static void soc_ref_qspi_write(void *opaque, hwaddr addr, uint64_t data,
                               unsigned size)
{
    soc_ref_window_write(opaque, addr, data, size, 0x5000);
}

static uint64_t soc_ref_ddr_status_read(void *opaque, hwaddr addr,
                                        unsigned size)
{
    return soc_ref_window_read(opaque, addr, size, 0x6000);
}

static void soc_ref_ddr_status_write(void *opaque, hwaddr addr,
                                     uint64_t data, unsigned size)
{
    soc_ref_window_write(opaque, addr, data, size, 0x6000);
}

static const MemoryRegionOps soc_ref_qspi_ops = {
    .read = soc_ref_qspi_read,
    .write = soc_ref_qspi_write,
    .endianness = DEVICE_LITTLE_ENDIAN,
    .valid = { .min_access_size = 4, .max_access_size = 4 },
};

static const MemoryRegionOps soc_ref_ddr_status_ops = {
    .read = soc_ref_ddr_status_read,
    .write = soc_ref_ddr_status_write,
    .endianness = DEVICE_LITTLE_ENDIAN,
    .valid = { .min_access_size = 4, .max_access_size = 4 },
};

/* Optional compatibility endpoint for a preloaded upstream Malta U-Boot.
 * The normal SoC UART is a 32-bit MMIO contract; Malta's NS16550 node uses
 * byte-spaced registers at the legacy PCI I/O address. */
static uint64_t soc_ref_malta_uart_read(void *opaque, hwaddr addr,
                                        unsigned size)
{
    MIPS32SocRefState *s = opaque;
    unsigned reg = addr & 7;

    if (reg == 2)
        return (s->uart_regs[1] & 0x2) ? 0x2 : 0x1;
    if (reg == 5)
        return 0x60;
    return reg < ARRAY_SIZE(s->uart_regs) ? s->uart_regs[reg] : 0;
}

static void soc_ref_malta_uart_write(void *opaque, hwaddr addr,
                                     uint64_t data, unsigned size)
{
    MIPS32SocRefState *s = opaque;
    unsigned reg = addr & 7;

    if (reg == 0) {
        putchar(data & 0xff);
        fflush(stdout);
        return;
    }
    if (reg < ARRAY_SIZE(s->uart_regs))
        s->uart_regs[reg] = data;
}

static const MemoryRegionOps soc_ref_malta_uart_ops = {
    .read = soc_ref_malta_uart_read,
    .write = soc_ref_malta_uart_write,
    .endianness = DEVICE_LITTLE_ENDIAN,
    .valid = {
        .min_access_size = 1,
        .max_access_size = 4,
    },
};

static void soc_ref_update_irq(MIPS32SocRefState *s)
{
    uint32_t pending = (s->pic_raw | s->pic_soft) & s->pic_mask;
    uint32_t active_prio = 0;
    uint32_t best_prio = 0;
    int best_id = -1;
    bool any_active = false;
    for (int i = 0; i < 32; ++i) {
        if (s->pic_active & (1U << i)) {
            any_active = true;
            if (s->pic_priority[i] > active_prio)
                active_prio = s->pic_priority[i];
        }
        if (pending & (1U << i) && (best_id < 0 ||
            s->pic_priority[i] > best_prio)) {
            best_id = i;
            best_prio = s->pic_priority[i];
        }
    }
    if (s->peripheral_trace &&
        (!s->trace_pic_valid || s->trace_pic_raw != s->pic_raw ||
         s->trace_pic_pending != pending || s->trace_pic_mask != s->pic_mask ||
         s->trace_pic_active != s->pic_active)) {
        uint32_t cause = s->cpu ? s->cpu->env.CP0_Cause : 0;
        uint32_t status = s->cpu ? s->cpu->env.CP0_Status : 0;
        unsigned vec_id = best_id < 0 ? 0xffU : (unsigned)best_id;
        bool accepted = best_id >= 0 &&
                        (!any_active || best_prio > active_prio);
        fprintf(s->peripheral_trace,
                "{\"kind\":\"vic\",\"raw\":\"0x%08x\","
                "\"pending\":\"0x%08x\",\"enable\":\"0x%08x\","
                "\"active\":\"0x%08x\",\"irq\":%u,\"vec_id\":%u,"
                "\"vec_prio\":%u,\"uart_irq\":%u,\"uart_rx_irq\":0,"
                "\"uart_tx_irq\":%u,\"cpu_accept\":%u,"
                "\"cause\":\"0x%08x\",\"status\":\"0x%08x\"}\n",
                s->pic_raw, pending, s->pic_mask, s->pic_active,
                accepted ? 1U : 0U, vec_id, best_prio,
                (s->pic_raw & (1U << 1)) ? 1U : 0U,
                (s->pic_raw & (1U << 1)) ? 1U : 0U,
                accepted ? 1U : 0U, cause, status);
        fflush(s->peripheral_trace);
        s->trace_pic_raw = s->pic_raw;
        s->trace_pic_pending = pending;
        s->trace_pic_mask = s->pic_mask;
        s->trace_pic_active = s->pic_active;
        s->trace_pic_valid = true;
    }
    if (s->irq_replay_enabled) {
        if (s->irq_replay_armed) {
            /* RTL replay enters through the external hardware IRQ line
             * (Status.IM2), while the source identity is supplied by the
             * mirrored VIC state above.  Pulse the line and force the CPU to
             * observe the boundary without leaving a level-triggered IRQ. */
            qemu_set_irq(s->cpu->env.irq[2], true);
            s->irq_replay_armed = false;
            bql_lock();
            cpu_interrupt(CPU(s->cpu), CPU_INTERRUPT_HARD);
            bql_unlock();
        }
    } else if (s->cpu) {
        qemu_set_irq(s->cpu->env.irq[2],
                     best_id >= 0 && (!any_active || best_prio > active_prio));
    }
}

static void soc_ref_release_scheduled_irq(MIPS32SocRefState *s, CPUState *cpu)
{
    uint32_t cause = g_array_index(s->irq_replay_causes, uint32_t,
                                   s->irq_release_index);
    uint32_t ip_mask = (cause >> 8) & 0xffU;
    bool timer = (cause & (1U << CP0Ca_TI)) != 0;
    bool epc_valid = g_array_index(s->irq_replay_epc_valid, bool,
                                   s->irq_release_index);
    uint32_t target_epc = g_array_index(s->irq_replay_epcs, uint32_t,
                                        s->irq_release_index);

    if (epc_valid) {
        s->irq_replay_epc = target_epc;
        s->irq_replay_epc_fixup = true;
    }

    if (soc_ref_irq_replay_debug) {
        fprintf(stderr,
                "SOC_REF_IRQ_REPLAY_RELEASE index=%u target=%" PRIu64
                " retire=%" PRIu64 " cycle_seq=%" PRIu64
                " pc=%08" PRIx64 " epc=%08" PRIx64
                " target_epc=%08" PRIx32 " epc_valid=%u"
                " cause=%08" PRIx32 " status=%08" PRIx32
                " hflags=%08" PRIx32 " typed=%u bd=%u early=%u"
                " s0=%08" PRIx64 " s1=%08" PRIx64
                " s2=%08" PRIx64 " sp=%08" PRIx64
                " ra=%08" PRIx64 "\n",
                s->irq_release_index,
                g_array_index(s->irq_release_after, uint64_t,
                              s->irq_release_index),
                s->retire_count, s->cpu_cycle_retire_seq,
                (uint64_t)s->cpu->env.active_tc.PC,
                (uint64_t)s->cpu->env.CP0_EPC,
                target_epc, epc_valid,
                (uint32_t)s->cpu->env.CP0_Cause,
                (uint32_t)s->cpu->env.CP0_Status,
                (uint32_t)s->cpu->env.hflags,
                g_array_index(s->irq_replay_typed, bool,
                              s->irq_release_index),
                s->irq_replay_bd_pending,
                (unsigned)s->irq_replay_early_release,
                (uint64_t)s->cpu->env.active_tc.gpr[16],
                (uint64_t)s->cpu->env.active_tc.gpr[17],
                (uint64_t)s->cpu->env.active_tc.gpr[18],
                (uint64_t)s->cpu->env.active_tc.gpr[29],
                (uint64_t)s->cpu->env.active_tc.gpr[31]);
        fflush(stderr);
    }

    if (timer) {
        CPUMIPSState *env = &s->cpu->env;
        unsigned irq = (env->CP0_IntCtl >> CP0IntCtl_IPTI) & 0x7;
        env->CP0_Cause |= 1U << CP0Ca_TI;
        if (s->cp0_linux_timer_phase == SOC_REF_LINUX_TIMER_LATE) {
            s->cp0_linux_timer_phase = SOC_REF_LINUX_TIMER_NATIVE;
            s->cp0_linux_timer_late_suppressed = false;
        }
        qemu_set_irq(env->irq[irq], true);
        bql_lock();
        cpu_interrupt(cpu, CPU_INTERRUPT_HARD);
        bql_unlock();
    }
    if (ip_mask & 0x04U) {
        s->irq_replay_armed = true;
    }
    ++s->irq_release_index;
    if (ip_mask & 0x04U) {
        soc_ref_update_irq(s);
    }
}

static void soc_ref_record_irq_pc(MIPS32SocRefState *s, target_ulong pc)
{
    s->irq_replay_pc_history[s->irq_replay_pc_history_next] = pc;
    s->irq_replay_pc_history_next =
        (s->irq_replay_pc_history_next + 1) % SOC_REF_IRQ_PC_HISTORY_SIZE;
    if (s->irq_replay_pc_history_count < SOC_REF_IRQ_PC_HISTORY_SIZE) {
        ++s->irq_replay_pc_history_count;
    }
}

static bool soc_ref_irq_pc_seen_recently(const MIPS32SocRefState *s,
                                         target_ulong pc, guint lookback)
{
    guint available = s->irq_replay_pc_history_count > 0 ?
        s->irq_replay_pc_history_count - 1 : 0;

    lookback = MIN(lookback, available);
    for (guint i = 0; i < lookback; ++i) {
        guint index = (s->irq_replay_pc_history_next +
                       SOC_REF_IRQ_PC_HISTORY_SIZE - 2 - i) %
                      SOC_REF_IRQ_PC_HISTORY_SIZE;
        if (s->irq_replay_pc_history[index] == pc) {
            return true;
        }
    }
    return false;
}

static bool soc_ref_irq_pc_path_has_backedge(const MIPS32SocRefState *s,
                                             guint lookback)
{
    guint available = s->irq_replay_pc_history_count > 0 ?
        s->irq_replay_pc_history_count - 1 : 0;

    lookback = MIN(lookback, available);
    for (guint i = 0; i < lookback; ++i) {
        guint newer_index = (s->irq_replay_pc_history_next +
                             SOC_REF_IRQ_PC_HISTORY_SIZE - 1 - i) %
                            SOC_REF_IRQ_PC_HISTORY_SIZE;
        guint older_index = (newer_index + SOC_REF_IRQ_PC_HISTORY_SIZE - 1) %
                            SOC_REF_IRQ_PC_HISTORY_SIZE;
        if (s->irq_replay_pc_history[newer_index] <
            s->irq_replay_pc_history[older_index]) {
            return true;
        }
    }
    return false;
}

static void soc_ref_instruction_tick(CPUState *cpu)
{
    MIPS32SocRefState *s = soc_ref_active_state;
    uint64_t release_after;
    bool release_early = false;
    bool release_late = false;
    target_ulong current_pc;

    if (!s || CPU(s->cpu) != cpu) {
        return;
    }
    current_pc = s->cpu->env.active_tc.PC;
    soc_ref_record_irq_pc(s, current_pc);
    ++s->retire_count;
    ++s->cpu_cycle_retire_seq;
    soc_ref_uart_retire_tick(s);
    soc_ref_cp0_retire_timer_tick(s);
    if (soc_ref_irq_replay_debug && soc_ref_irq_trace_context_index >= 0 &&
        s->irq_release_index == (guint)soc_ref_irq_trace_context_index &&
        s->cpu_cycle_retire_seq <= g_array_index(s->irq_release_after,
                                                 uint64_t,
                                                 s->irq_release_index) &&
        s->cpu_cycle_retire_seq + soc_ref_irq_trace_context_window >=
            g_array_index(s->irq_release_after, uint64_t,
                          s->irq_release_index)) {
        uint64_t target = g_array_index(s->irq_release_after, uint64_t,
                                        s->irq_release_index);
        fprintf(stderr,
                "SOC_REF_IRQ_REPLAY_CONTEXT index=%u target=%" PRIu64
                " retire=%" PRIu64 " cycle_seq=%" PRIu64
                " pc=%08" PRIx64
                " hflags=%08" PRIx32 " s0=%08" PRIx64
                " s1=%08" PRIx64 " a0=%08" PRIx64
                " sp=%08" PRIx64 " ra=%08" PRIx64 "\n",
                s->irq_release_index, target, s->retire_count,
                s->cpu_cycle_retire_seq,
                (uint64_t)s->cpu->env.active_tc.PC,
                (uint32_t)s->cpu->env.hflags,
                (uint64_t)s->cpu->env.active_tc.gpr[16],
                (uint64_t)s->cpu->env.active_tc.gpr[17],
                (uint64_t)s->cpu->env.active_tc.gpr[4],
                (uint64_t)s->cpu->env.active_tc.gpr[29],
                (uint64_t)s->cpu->env.active_tc.gpr[31]);
        fflush(stderr);
    }
    if (!s->irq_replay_enabled && !s->cp0_trace && !s->cp0_retire_clock) {
        return;
    }
    if (s->cp0_trace && s->cp0_trace_interval != 0 &&
        (s->retire_count % s->cp0_trace_interval) == 0) {
        fprintf(s->cp0_trace,
                "{\"seq\":%" PRIu64 ",\"pc\":\"0x%08" PRIx64
                "\",\"count\":\"0x%08x\",\"compare\":\"0x%08x\","
                "\"cause\":\"0x%08x\",\"status\":\"0x%08x\"}\n",
                s->retire_count,
                (uint64_t)s->cpu->env.active_tc.PC,
                cpu_mips_get_count(&s->cpu->env),
                (uint32_t)s->cpu->env.CP0_Compare,
                (uint32_t)s->cpu->env.CP0_Cause,
                (uint32_t)s->cpu->env.CP0_Status);
        fflush(s->cp0_trace);
    }
    if (!s->irq_replay_enabled) {
        return;
    }
    if (s->irq_replay_wake_pending) {
        s->irq_replay_wake_pending = false;
        /* The RTL records the WAIT wakeup exception against the sequential
         * instruction at the wake boundary, before that instruction retires. */
        if (!s->irq_replay_epc_fixup) {
            s->irq_replay_epc = s->cpu->env.active_tc.PC;
            s->irq_replay_epc_fixup = true;
        }
        bql_lock();
        cpu_interrupt(cpu, CPU_INTERRUPT_HARD);
        bql_unlock();
        cpu_loop_exit_noexc(cpu);
        return;
    }
    if (s->irq_release_index >= s->irq_release_after->len) {
        return;
    }
    release_after = g_array_index(s->irq_release_after, uint64_t,
                                  s->irq_release_index);
    /* IRQ schedules use the RTL retirement coordinate. retire_count remains
     * the synthetic CP0 Count source and can lag after CP0 schedule resyncs. */
    if (s->cpu_cycle_retire_seq > release_after) {
        bool typed = g_array_index(s->irq_replay_typed, bool,
                                   s->irq_release_index);
        bool epc_valid = g_array_index(s->irq_replay_epc_valid, bool,
                                       s->irq_release_index);
        uint64_t late_delta = s->cpu_cycle_retire_seq - release_after;

        /* A synchronous exception is accounted in QEMU's exception-entry
         * path, so a schedule boundary on that exception can be observed by
         * the next normal retire hook. Preserve its captured EPC and allow
         * only that single boundary crossing. */
        if (!typed || !epc_valid || late_delta != 1) {
            return;
        }
        release_late = true;
    } else if (s->cpu_cycle_retire_seq < release_after) {
        bool typed = g_array_index(s->irq_replay_typed, bool,
                                   s->irq_release_index);
        bool epc_valid = g_array_index(s->irq_replay_epc_valid, bool,
                                       s->irq_release_index);
        uint32_t target_epc = g_array_index(s->irq_replay_epcs, uint32_t,
                                            s->irq_release_index);
        guint pc_lookback;

        /* The RTL can capture an IRQ before the EPC instruction retires.
         * Stop one tick early when QEMU is already at that EPC; a previous
         * CP0 Count resynchronization alone does not justify a larger jump. */
        uint64_t early_delta = release_after - s->cpu_cycle_retire_seq;
        pc_lookback = early_delta < SOC_REF_IRQ_PC_HISTORY_SIZE ?
            early_delta + 1 : SOC_REF_IRQ_PC_HISTORY_SIZE - 1;
        if (early_delta == 0 ||
            early_delta > SOC_REF_IRQ_EARLY_RELEASE_MAX_TICKS ||
            !typed || !epc_valid ||
            (uint32_t)current_pc != target_epc ||
            soc_ref_irq_pc_seen_recently(s, current_pc, pc_lookback) ||
            (early_delta == SOC_REF_IRQ_EARLY_RELEASE_MAX_TICKS &&
             soc_ref_irq_pc_path_has_backedge(s, pc_lookback))) {
            return;
        }
        release_early = true;
    }
    uint32_t replay_cause = g_array_index(s->irq_replay_causes, uint32_t,
                                          s->irq_release_index);
    bool typed = g_array_index(s->irq_replay_typed, bool,
                               s->irq_release_index);
    /* A typed RTL Cause sample is authoritative for BD. Legacy schedules
     * retain QEMU's delay-slot fallback. */
    s->irq_replay_bd_pending =
        ((replay_cause & (1U << CP0Ca_BD)) != 0) ||
        ((s->irq_release_index < 32 &&
          (s->irq_replay_bd_mask & (1U << s->irq_release_index)) != 0)) ||
        (!typed && (s->cpu->env.hflags & MIPS_HFLAG_BMASK) != 0);
    s->irq_replay_bd_valid = typed;
    /* The RTL VIC schedule samples a pending source at the retire boundary
     * before the next sequential instruction is fetched.  QEMU's interrupt
     * path observes the already-advanced PC for subsequent replay entries;
     * recover the RTL EPC boundary without changing ordinary IRQ replay. */
    if (s->irq_replay_pic_mask && s->irq_release_index > 0) {
        s->irq_replay_epc = s->irq_replay_bd_pending ?
            s->cpu->env.active_tc.PC - 4 : s->cpu->env.active_tc.PC;
        s->irq_replay_epc_fixup = true;
    }
    if (s->irq_release_index == 0 && s->irq_replay_pic_mask) {
        /* Some RTL IRQ replays originate in the SoC VIC.  The CPU replay
         * line is injected independently, so mirror the explicitly supplied
         * VIC software sources before delivering the first exception. */
        s->pic_soft |= s->irq_replay_pic_mask;
        s->pic_mask |= s->irq_replay_pic_mask;
    }
    s->irq_replay_early_release = release_early && !release_late;
    soc_ref_release_scheduled_irq(s, cpu);
    /* This hook runs before the current guest instruction.  Exit now so the
     * pending interrupt is accepted at the scheduled boundary, not after the
     * instruction (which can be a branch delay slot) executes. */
    cpu_loop_exit_noexc(cpu);
}

void qemu_mips32_soc_ref_interrupt_fixup(CPUMIPSState *env)
{
    MIPS32SocRefState *s = soc_ref_active_state;
    if (s && s->irq_replay_epc_fixup) {
        env->CP0_EPC = s->irq_replay_epc;
        s->irq_replay_epc_fixup = false;
    }
}

/* Retained as a no-op for the project-local CPU-exec hook compatibility. */
void qemu_mips32_soc_ref_retire_tick(CPUState *cpu)
{
    (void)cpu;
}

/* WAIT is a non-returning translated instruction, so the generic retire hook
 * cannot observe its retirement. Release replay SW0 at the WAIT boundary. */
void qemu_mips32_soc_ref_wait(CPUMIPSState *env)
{
    MIPS32SocRefState *s = soc_ref_active_state;
    uint64_t release_after;
    bool typed;

    if (s && s->cpu && &s->cpu->env == env) {
        ++s->cpu_cycle_retire_seq;
        ++s->retire_count;
        soc_ref_uart_retire_tick(s);
    }

    if (s && s->cp0_retire_clock && !s->irq_replay_has_timer &&
        qemu_mips32_soc_ref_cp0_timer_armed()) {
        uint32_t count = qemu_mips32_soc_ref_cp0_retire_ticks(env);
        uint32_t delta = s->cpu ? (uint32_t)(env->CP0_Compare - count) : 0;
        s->retire_count += delta;
        soc_ref_cp0_retire_timer_tick(s);
        bql_lock();
        cpu_interrupt(env_cpu(env), CPU_INTERRUPT_WAKE);
        bql_unlock();
        return;
    }

    if (!s || !s->irq_replay_enabled ||
        s->irq_release_index >= s->irq_release_after->len) {
        return;
    }
    release_after = g_array_index(s->irq_release_after, uint64_t,
                                  s->irq_release_index);
    if (s->cpu_cycle_retire_seq != release_after) {
        return;
    }
    typed = g_array_index(s->irq_replay_typed, bool, s->irq_release_index);
    /* WAIT wakeups use the same post-acceptance Cause contract as ordinary
     * replay entries; retain QEMU's native delay-slot bit as a fallback. */
    s->irq_replay_bd_pending =
        (((g_array_index(s->irq_replay_causes, uint32_t,
                         s->irq_release_index) & (1U << CP0Ca_BD)) != 0)) ||
        (s->irq_release_index < 32 &&
         (s->irq_replay_bd_mask & (1U << s->irq_release_index)) != 0) ||
        (!typed && (env->hflags & MIPS_HFLAG_BMASK) != 0);
    s->irq_replay_bd_valid = typed;
    if (typed) {
        s->irq_replay_early_release = false;
        soc_ref_release_scheduled_irq(s, env_cpu(env));
    } else {
        ++s->irq_release_index;
        qemu_set_irq(env->irq[0], true);
    }
    bql_lock();
    s->irq_replay_wake_pending = true;
    cpu_interrupt(env_cpu(env), CPU_INTERRUPT_WAKE);
    bql_unlock();
}

void helper_soc_ref_retire_tick(CPUMIPSState *env)
{
    soc_ref_instruction_tick(env_cpu(env));
}

void qemu_mips32_soc_ref_sync_exception(CPUMIPSState *env)
{
    MIPS32SocRefState *s = soc_ref_active_state;

    if (!s || !s->cpu || &s->cpu->env != env) {
        return;
    }
    soc_ref_record_irq_pc(s, env->active_tc.PC);
    ++s->retire_count;
    ++s->cpu_cycle_retire_seq;
    soc_ref_uart_retire_tick(s);
    soc_ref_cp0_retire_timer_tick(s);
}

static int soc_ref_pic_best(MIPS32SocRefState *s, uint32_t *priority)
{
    uint32_t pending = (s->pic_raw | s->pic_soft) & s->pic_mask;
    int best = -1;
    *priority = 0;
    for (int i = 0; i < 32; ++i) {
        if (pending & (1U << i) && (best < 0 ||
            s->pic_priority[i] > *priority)) {
            best = i;
            *priority = s->pic_priority[i];
        }
    }
    return best;
}

static hwaddr soc_ref_dma_addr(uint32_t addr)
{
    if ((addr & 0xe0000000U) == 0x80000000U ||
        (addr & 0xe0000000U) == 0xa0000000U) {
        return addr & 0x1fffffffU;
    }
    return addr;
}

static void soc_ref_timer_cb(void *opaque)
{
    MIPS32SocRefState *s = opaque;
    if (s->timer_ctrl & 1) {
        s->timer_value = s->timer_load;
        if (s->timer_ctrl & 2) {
            s->timer_int = 1;
            /* RTL irq_sources maps timer_int to VIC source 2. */
            s->pic_raw |= 1U << 2;
        }
        soc_ref_update_irq(s);
        if (s->timer_load) {
            s->timer_deadline = qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL) +
                                 (uint64_t)s->timer_load * 20;
            timer_mod(s->timer, s->timer_deadline);
        }
    }
}

static uint32_t soc_ref_timer_value(MIPS32SocRefState *s)
{
    uint64_t now, remaining;
    if (!(s->timer_ctrl & 1) || !s->timer_load || !s->timer_deadline) {
        return s->timer_value;
    }
    now = qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL);
    if (now >= s->timer_deadline) {
        s->timer_value = 0;
        return 0;
    }
    remaining = s->timer_deadline - now;
    s->timer_value = (remaining + 19) / 20; /* 50 MHz reference clock */
    return s->timer_value;
}

static void soc_ref_wdt_cb(void *opaque)
{
    MIPS32SocRefState *s = opaque;

    if (!(s->wdt_ctrl & 1U))
        return;
    s->wdt_value = 0;
    s->wdt_ctrl &= ~1U;
    s->wdt_expired = true;
    s->boot_reset_cause |= 2U;
    qemu_system_reset_request(SHUTDOWN_CAUSE_GUEST_RESET);
}

static void soc_ref_wdt_reset(void *opaque)
{
    MIPS32SocRefState *s = opaque;

    /* The RTL WDT is in the always-on domain: expiry and boot diagnostics
     * survive the reset pulse, while the running counter and enable clear. */
    s->wdt_ctrl &= ~1U;
    s->wdt_value = 0;
    timer_del(s->wdt_timer);
}

static void soc_ref_dma_start(MIPS32SocRefState *s)
{
    uint8_t buf[256];
    uint32_t left = s->dma_len;
    hwaddr src = soc_ref_dma_addr(s->dma_src);
    hwaddr dst = soc_ref_dma_addr(s->dma_dst);
    MemTxResult result = MEMTX_OK;

    s->dma_status = 1; /* legacy CTRL bit 0: busy */
    if (s->dma_src || s->dma_dst || s->dma_len)
        soc_ref_dma_event_legacy(s, "START", 0, 0);
    if (soc_ref_dma_reset_inflight && !s->dma_reset_injected) {
        /* Keep the first transaction genuinely in flight: the reset request
         * is queued before any source data is copied.  The reset callback
         * clears the DMA state; the restarted guest must issue a new start. */
        s->dma_reset_injected = true;
        soc_ref_dma_event_legacy(s, "RESET_IN_FLIGHT", 0, 0);
        qemu_system_reset_request(SHUTDOWN_CAUSE_GUEST_RESET);
        return;
    }
    while (left) {
        uint32_t n = MIN(left, (uint32_t)sizeof(buf));
        result = address_space_read(&address_space_memory, src,
                                    MEMTXATTRS_UNSPECIFIED, buf, n);
        if (result != MEMTX_OK) break;
        result = address_space_write(&address_space_memory, dst,
                                     MEMTXATTRS_UNSPECIFIED, buf, n);
        if (result != MEMTX_OK) break;
        src += n;
        dst += n;
        left -= n;
    }
    /* Keep the architectural BUSY/DONE read sequence aligned with the RTL
     * legacy mover.  The copy itself remains immediate; only the visible
     * completion boundary is modeled here. */
    s->dma_completion_status = result == MEMTX_OK ? 4 : (4 | 0x10);
    /* Small legacy transfers complete in the same architectural window as
     * the RTL model after the guest's settling delay.  Larger transfers keep
     * a bounded read-side latency so software can still exercise BUSY
     * polling without making the reference timing part of the contract. */
    s->dma_polls_remaining = s->dma_len <= 4 ? 0 : 4 + (s->dma_len / 2) - 1;
    if (s->dma_polls_remaining == 0) {
        s->dma_status = s->dma_completion_status;
        if (s->dma_src || s->dma_dst || s->dma_len)
            soc_ref_dma_event_legacy(s, "DONE", (s->dma_status & 0x10) != 0,
                                     (s->dma_status & 0x10) ? 2 : 0);
        if (s->dma_ctrl & 2) {
            s->pic_raw |= 1U << 3;
            soc_ref_update_irq(s);
            soc_ref_dma_event(s, "IRQ", 0, 0, 0, 1);
        }
    }
}

static void soc_ref_dma_reset(void *opaque)
{
    MIPS32SocRefState *s = opaque;

    s->dma_src = 0;
    s->dma_dst = 0;
    s->dma_len = 0;
    s->dma_ctrl = 0;
    s->dma_status = 0;
    s->dma_completion_status = 0;
    s->dma_polls_remaining = 0;
    for (unsigned ch = 0; ch < 4; ++ch) {
        s->dma_v2_ctrl[ch] = 0;
        s->dma_v2_status[ch] = 0;
        s->dma_v2_err_code[ch] = 0;
        s->dma_v2_polls_remaining[ch] = 0;
    }
    s->pic_raw &= ~((1U << 3) | (1U << 4) | (1U << 5) | (1U << 6));
    soc_ref_update_irq(s);
}

static void soc_ref_dma_v2_start(MIPS32SocRefState *s, unsigned ch)
{
    uint8_t buf[256];
    uint32_t left = s->dma_v2_len[ch];
    hwaddr src = soc_ref_dma_addr(s->dma_v2_src[ch]);
    hwaddr dst = soc_ref_dma_addr(s->dma_v2_dst[ch]);
    MemTxResult result = MEMTX_OK;
    bool read_failed = false;

    s->dma_v2_status[ch] = 1; /* BUSY */
    soc_ref_dma_event(s, "START", ch, 0, 0, 0);
    s->dma_v2_polls_remaining[ch] = 4 + (s->dma_v2_len[ch] / 4) +
                                    (s->dma_v2_len[ch] > 16 ? 1 : 0);
    if (s->dma_v2_ctrl[ch] & 4)
        s->dma_v2_polls_remaining[ch]++;
    s->dma_v2_err_code[ch] = 0;
    /* SG mode is selected by CTRL, so its descriptor head is authoritative
     * even though the direct-transfer LEN CSR is unused and remains zero. */
    if (s->dma_v2_ctrl[ch] & 2) {
        uint32_t desc = s->dma_v2_desc_head[ch];
        unsigned count = 0;
        s->dma_v2_status[ch] = 1;
        while (desc && count < 16) {
            uint32_t words[4];
            hwaddr daddr = soc_ref_dma_addr(desc);
            if ((desc & 3) || address_space_read(&address_space_memory, daddr,
                    MEMTXATTRS_UNSPECIFIED, words, sizeof(words)) != MEMTX_OK) {
                s->dma_v2_status[ch] = 2 | 4;
                s->dma_v2_err_code[ch] = 4;
                break;
            }
            if ((words[0] | words[1] | words[2] | words[3]) & 3 ||
                (words[2] == 0 && words[3] != 0)) {
                s->dma_v2_status[ch] = 2 | 4;
                s->dma_v2_err_code[ch] = 4;
                break;
            }
            left = words[2];
            src = soc_ref_dma_addr(words[0]);
            dst = soc_ref_dma_addr(words[1]);
            while (left) {
                uint32_t n = MIN(left, (uint32_t)sizeof(buf));
                if (s->dma_fault_mode == 1) {
                    result = MEMTX_ERROR;
                    read_failed = true;
                } else {
                    result = address_space_read(&address_space_memory, src,
                                                MEMTXATTRS_UNSPECIFIED, buf, n);
                    read_failed = result != MEMTX_OK;
                }
                if (result != MEMTX_OK) break;
                if (s->dma_fault_mode == 2) {
                    result = MEMTX_ERROR;
                } else {
                    result = address_space_write(&address_space_memory, dst,
                                                 MEMTXATTRS_UNSPECIFIED, buf, n);
                }
                if (result != MEMTX_OK) break;
                src += n; dst += n; left -= n;
            }
            if (result != MEMTX_OK) {
                s->dma_v2_status[ch] = 2 | 4;
                s->dma_v2_err_code[ch] = read_failed ? 2 : 3;
                break;
            }
            desc = words[3];
            count++;
        }
        if (count >= 16 && desc) {
            s->dma_v2_status[ch] = 2 | 4;
            s->dma_v2_err_code[ch] = 5;
        } else if (!s->dma_v2_err_code[ch]) {
            s->dma_v2_status[ch] = 2;
        }
        s->dma_v2_polls_remaining[ch] = 0;
        soc_ref_dma_event(s, "DONE", ch, (s->dma_v2_status[ch] & 4) != 0,
                          s->dma_v2_err_code[ch], 0);
    } else if (s->dma_v2_len[ch] == 0) {
        s->dma_v2_status[ch] = 2; /* zero-length completes immediately */
        s->dma_v2_polls_remaining[ch] = 0;
        soc_ref_dma_event(s, "DONE", ch, 0, 0, 0);
    } else if ((s->dma_v2_src[ch] | s->dma_v2_dst[ch] | s->dma_v2_len[ch]) & 3) {
        s->dma_v2_status[ch] = 2 | 4;
        s->dma_v2_polls_remaining[ch] = 0;
        s->dma_v2_err_code[ch] = 1; /* alignment */
        soc_ref_dma_event(s, "DONE", ch, 1, 1, 0);
    } else {
        while (left) {
            uint32_t n = MIN(left, (uint32_t)sizeof(buf));
            if (s->dma_fault_mode == 1) {
                result = MEMTX_ERROR;
                read_failed = true;
            } else {
                result = address_space_read(&address_space_memory, src,
                                            MEMTXATTRS_UNSPECIFIED, buf, n);
                read_failed = result != MEMTX_OK;
            }
            if (result != MEMTX_OK) break;
            if (s->dma_fault_mode == 2) {
                result = MEMTX_ERROR;
            } else {
                result = address_space_write(&address_space_memory, dst,
                                             MEMTXATTRS_UNSPECIFIED, buf, n);
            }
            if (result != MEMTX_OK) break;
            src += n;
            dst += n;
            left -= n;
        }
        if (result != MEMTX_OK) {
            s->dma_v2_status[ch] = 2 | 4;
            s->dma_v2_err_code[ch] = read_failed ? 2 : 3;
            soc_ref_dma_event(s, "DONE", ch, 1, s->dma_v2_err_code[ch], 0);
        }
    }
    if ((s->dma_v2_ctrl[ch] & 4) && (s->dma_v2_status[ch] & (2 | 4))) {
        s->pic_raw |= 1U << (3 + ch);
        soc_ref_update_irq(s);
        soc_ref_dma_event(s, "IRQ", ch, 0, 0, 1);
    }
}

/* Transaction-level QSPI model.  The RTL command block owns pin timing; the
 * reference machine only needs the deterministic APB-visible command/FIFO
 * contract and an image-backed flash endpoint. */
static void soc_ref_qspi_clear(MIPS32SocRefState *s)
{
    s->qspi_ctrl = 0;
    s->qspi_clk_div = 0;
    s->qspi_cs_ctrl = 0;
    s->qspi_irq_en = 0;
    s->qspi_timeout_limit = 4096;
    s->qspi_cmd_addr = 0;
    s->qspi_cmd_len = 0;
    s->qspi_tx_count = 0;
    s->qspi_rx_count = 0;
    s->qspi_busy_polls = 0;
    s->qspi_status = 0;
    s->qspi_irq_status = 0;
    s->qspi_rx_head = s->qspi_rx_tail = 0;
    s->qspi_tx_head = s->qspi_tx_tail = 0;
    memset(s->qspi_lut, 0, sizeof(s->qspi_lut));
}

static void soc_ref_qspi_complete(MIPS32SocRefState *s, bool error,
                                  uint32_t error_code)
{
    s->qspi_status &= ~1U;
    s->qspi_status |= error ? (1U << 4) : 0;
    s->qspi_status |= 1U << 3; /* IRQ/DONE */
    s->qspi_irq_status |= 1U;
    if (error)
        s->qspi_timeout = error_code == 0x00010001;
    if (s->qspi_irq_en & 1)
        /* RTL irq_sources maps qspi_irq to VIC source 4. */
        s->pic_raw |= 1U << 4;
    soc_ref_update_irq(s);
}

static void soc_ref_qspi_start(MIPS32SocRefState *s, uint32_t index)
{
    uint32_t lut = s->qspi_lut[index & 7];
    uint32_t len = s->qspi_cmd_len;
    uint32_t addr = s->qspi_cmd_addr;
    bool write = (lut >> 17) & 1;
    uint8_t *flash = memory_region_get_ram_ptr(&s->flash);

    if (!(s->qspi_ctrl & 1)) {
        s->qspi_status |= (1U << 4) | (1U << 3) | (1U << 6);
        s->qspi_irq_status |= 4;
        return;
    }
    if (s->qspi_status & 1) {
        s->qspi_status |= (1U << 4) | (1U << 3);
        s->qspi_irq_status |= 1;
        return;
    }
    s->qspi_status &= ~((1U << 3) | (1U << 4) | (1U << 5) | (1U << 6));
    s->qspi_status |= 1;
    s->qspi_busy_polls = 2 + (len != 0);
    if (s->qspi_timeout_limit && s->qspi_busy_polls > s->qspi_timeout_limit) {
        s->qspi_status &= ~1U;
        s->qspi_status |= (1U << 4) | (1U << 5) | (1U << 3);
        s->qspi_irq_status |= 3;
        s->qspi_timeout = true;
        return;
    }
    if (addr + len > SOC_FLASH_SIZE) {
        soc_ref_qspi_complete(s, true, 0x00030001);
        return;
    }
    if (len == 0) {
        soc_ref_qspi_complete(s, false, 0);
        return;
    }
    if (write) {
        for (uint32_t i = 0; i < len; ++i) {
            uint32_t word = s->qspi_tx_count ? s->qspi_tx_fifo[s->qspi_tx_head] : 0;
            if (s->qspi_tx_count) {
                s->qspi_tx_head = (s->qspi_tx_head + 1) & 31;
                s->qspi_tx_count--;
            }
            flash[addr + i] = (uint8_t)(word >> (24 - ((i & 3) * 8)));
        }
    } else {
        s->qspi_rx_count = 0;
        s->qspi_rx_head = s->qspi_rx_tail = 0;
        for (uint32_t i = 0; i < len && i < 32; ++i) {
            s->qspi_rx_fifo[s->qspi_rx_tail] = flash[addr + i];
            s->qspi_rx_tail = (s->qspi_rx_tail + 1) & 31;
            s->qspi_rx_count++;
        }
    }
}

static uint32_t soc_ref_ipi_status_read(MIPS32SocRefState *s, unsigned bank)
{
    uint32_t status = s->ipi_status[bank];

    /* The RTL target emits its ACK one clock after invalidate_valid. A
     * polling load is the observable boundary in this machine, so expose
     * one busy/pending sample before completing the transaction. */
    if (s->ipi_busy_reads[bank] != 0) {
        s->ipi_busy_reads[bank]--;
        if (s->ipi_busy_reads[bank] == 0) {
            s->ipi_status[bank] &= ~((1U << 0) | (1U << 1));
            if (s->ipi_fault[bank] & (1U << 2)) {
                s->ipi_status[bank] |= (1U << 3) | (1U << 5);
            } else if (s->ipi_fault[bank] & (1U << 1)) {
                s->ipi_status[bank] |= 1U << 3;
            } else {
                s->ipi_status[bank] |= 1U << 2;
            }
        }
        status = s->ipi_status[bank];
    }
    return status;
}

static void soc_ref_ipi_send(MIPS32SocRefState *s, unsigned bank)
{
    uint32_t fault = s->ipi_fault[bank] & 0xfU;

    if (s->ipi_status[bank] & (1U << 0)) {
        s->ipi_status[bank] |= 1U << 4;
        return;
    }
    s->ipi_status[bank] &= ~((1U << 2) | (1U << 3));
    if (fault & 1U) {
        s->ipi_status[bank] |= 1U << 3;
        return;
    }
    s->ipi_status[bank] |= (1U << 0) | (1U << 1);
    s->ipi_busy_reads[bank] = (fault & (1U << 2)) ? 65U : 2U;
}

static uint64_t soc_ref_apb_read(void *opaque, hwaddr addr, unsigned size)
{
    MIPS32SocRefState *s = opaque;
    uint32_t off = addr & 0xffff;
    uint32_t value = 0;
    uint32_t priority;
    if (off < 0x1000) return soc_ref_uart_read(s, off, size);
    if ((off & 0xf000) == 0xa000 || (off & 0xf000) == 0xb000) {
        unsigned bank = ((off & 0xf000) == 0xb000) ? 1U : 0U;
        switch (off & 0xff) {
        case 0x20: value = (s->ipi_generation[bank] << 8) |
                              (s->ipi_target[bank] & 1U); break;
        case 0x24: value = s->ipi_asid[bank] & 0xffU; break;
        case 0x28: value = s->ipi_vpn[bank] & 0xfffffU; break;
        case 0x2c: value = s->ipi_scope[bank] & 3U; break;
        case 0x34: value = soc_ref_ipi_status_read(s, bank); break;
        case 0x3c: value = s->ipi_fault[bank] & 0xfU; break;
        default: value = 0; break;
        }
        return value;
    }
    switch (off) {
    case 0x9000:
        value = s->mmu_context_asid_generation;
        break;
    case 0x9004:
        value = s->mmu_context_vpn;
        break;
    case 0x9008:
        value = s->mmu_context_scope;
        break;
    case 0x9024:
        value = s->mmu_context_status;
        break;
    case 0x900c:
        value = s->mmu_context_event & 0xfU;
        break;
    case 0x9028:
        value = s->mmu_root_value;
        break;
    case 0x902c:
        value = s->mmu_root_value_generation;
        break;
    case 0x9034:
        value = s->mmu_root_event & 0xfU;
        break;
    case 0x9040:
        value = s->mmu_page_value;
        break;
    case 0x9044:
        value = s->mmu_page_value_generation;
        break;
    case 0x904c:
        value = s->mmu_page_event & 0xfU;
        break;
    case 0x1000: value = s->timer_ctrl; break;
    case 0x1004: value = s->timer_load; break;
    case 0x1008: value = soc_ref_timer_value(s); break;
    case 0x100c: value = s->timer_int; break;
    case 0x7000: value = (s->wdt_ctrl & 1U) | (s->wdt_lock ? 2U : 0U); break;
    case 0x7004: value = s->wdt_load; break;
    case 0x7008:
        value = s->wdt_value;
        /* Bare-metal reference guests commonly spin in a short MMIO poll.
         * Advance one virtual watchdog tick at that observation boundary so
         * expiry remains deterministic even when a tight TCG loop does not
         * yield enough host virtual-clock time for the timer callback. */
        if ((s->wdt_ctrl & 1U) && s->wdt_value) {
            s->wdt_value--;
            if (s->wdt_value == 0)
                soc_ref_wdt_cb(s);
        }
        break;
    case 0x7010: value = s->wdt_expired ? 1U : 0U; break;
    case 0x8000: value = s->boot_stage & 0xffU; break;
    case 0x8004: value = s->boot_failure; break;
    case 0x8008: value = s->boot_reset_cause & 3U; break;
    case 0x2000: value = (s->gpio_data & s->gpio_dir) |
                              (s->gpio_input & ~s->gpio_dir); break;
    case 0x2004: value = s->gpio_dir; break;
    case 0x3000: value = s->dma_src; break;
    case 0x3004: value = s->dma_dst; break;
    case 0x3008: value = s->dma_len; break;
    case 0x300c:
        value = s->dma_status;
        if ((s->dma_status & 1) && s->dma_polls_remaining) {
            if (--s->dma_polls_remaining == 0) {
                s->dma_status = s->dma_completion_status;
                if (s->dma_src || s->dma_dst || s->dma_len)
                    soc_ref_dma_event_legacy(s, "DONE", (s->dma_status & 0x10) != 0,
                                             (s->dma_status & 0x10) ? 2 : 0);
                if (s->dma_ctrl & 2) {
                    s->pic_raw |= 1U << 3; /* RTL legacy DMA source is VIC bit 3. */
                    soc_ref_update_irq(s);
                    soc_ref_dma_event(s, "IRQ", 0, 0, 0, 1);
                }
            }
        }
        break;
    case 0x3104:
        /* DMA v2 IRQ_STATUS: INT_EN & (DONE | ERR), one bit per channel. */
        value = 0;
        for (unsigned irq_ch = 0; irq_ch < 4; ++irq_ch) {
            if ((s->dma_v2_ctrl[irq_ch] & 4) &&
                (s->dma_v2_status[irq_ch] & (2 | 4)))
                value |= 1U << irq_ch;
        }
        break;
    case 0x3010: value = 0; break; /* no legacy status register in RTL */
    default:
        if (off >= 0x3040 && off < 0x3140) {
            unsigned ch = (off - 0x3040) >> 6;
            unsigned reg = (off - 0x3040) & 0x3f;
            if (ch < 4) {
                switch (reg) {
                case 0x00: value = (s->dma_v2_err_code[ch] << 5) |
                                      ((s->dma_v2_status[ch] & 4) ? 0x10 : 0) |
                                      ((s->dma_v2_status[ch] & 2) ? 0x08 : 0) |
                                      (s->dma_v2_ctrl[ch] & 0x06) |
                                      ((s->dma_v2_status[ch] & 1) ? 1 : 0); break;
                case 0x04: value = s->dma_v2_src[ch]; break;
                case 0x08: value = s->dma_v2_dst[ch]; break;
                case 0x0c: value = s->dma_v2_len[ch]; break;
                case 0x10: value = s->dma_v2_desc_head[ch]; break;
                case 0x14:
                                      if ((s->dma_v2_status[ch] & 1) &&
                                          s->dma_v2_polls_remaining[ch] &&
                                          --s->dma_v2_polls_remaining[ch] == 0) {
                                          s->dma_v2_status[ch] = 2;
                                          soc_ref_dma_event(s, "DONE", ch, 0, 0, 0);
                                      }
                                      /* A zero-length or immediate model
                                       * completion may already be DONE when
                                       * the first status read arrives. The
                                       * architectural IRQ is still generated
                                       * at that observable completion read. */
                                      if ((s->dma_v2_status[ch] & 2) &&
                                          (s->dma_v2_ctrl[ch] & 4) &&
                                          !(s->pic_raw & (1U << (3 + ch)))) {
                                          s->pic_raw |= 1U << (3 + ch);
                                          soc_ref_update_irq(s);
                                          soc_ref_dma_event(s, "IRQ", ch, 0, 0, 1);
                                      }
                                      value = (s->dma_v2_status[ch] & 1) |
                                      (s->dma_v2_status[ch] & 2) |
                                      (s->dma_v2_status[ch] & 4) |
                                      ((s->dma_v2_status[ch] & 4) ?
                                       (s->dma_v2_err_code[ch] << 3) : 0); break;
                default: value = 0; break;
                }
            }
        }
        break;
    }
    switch (off) {
    case 0x4000: value = s->pic_raw | s->pic_soft; break;
    case 0x4004: value = s->pic_mask; break;
    case 0x4008: value = (s->pic_raw | s->pic_soft) & s->pic_mask; break;
    case 0x4014: value = s->pic_type; break;
    case 0x4018: value = s->pic_polarity; break;
    case 0x401c: value = s->pic_soft; break;
    case 0x4200:
        value = (uint32_t)(soc_ref_pic_best(s, &priority) < 0 ?
                           0xff : soc_ref_pic_best(s, &priority));
        /* A VEC_ID read only accepts an interrupt that can preempt the
         * current active priority, exactly as apb_vic's rd && irq path. */
        if (value != 0xff) {
            uint32_t active_prio = 0;
            bool any_active = false;
            for (int i = 0; i < 32; ++i) {
                if (s->pic_active & (1U << i)) {
                    any_active = true;
                    if (s->pic_priority[i] > active_prio)
                        active_prio = s->pic_priority[i];
                }
            }
            if (!any_active || priority > active_prio)
                s->pic_active |= 1U << value;
        }
        soc_ref_update_irq(s);
        break;
    case 0x4204:
        (void)soc_ref_pic_best(s, &priority);
        value = priority;
        break;
    case 0x420c: value = s->pic_active; break;
    case 0x4210:
        value = 0;
        for (int i = 0; i < 32; ++i)
            if ((s->pic_active & (1U << i)) && s->pic_priority[i] > value)
                value = s->pic_priority[i];
        break;
    case 0x5000: value = 0x51535001; break;
    /* The differential guest uses the image-backed XIP endpoint.  In the
     * RTL configuration that endpoint leaves controller_present low while
     * still exposing the status block and XIP window. */
    case 0x5004: value = 0; break;
    case 0x5008: value = s->qspi_timeout ? 0x00010001 : 0; break;
    case 0x500c: value = 0; break;
    /* Match the APB-visible apb_ddr4_status contract: VERSION, STATUS,
     * ERROR, CONTROL(W1C).  The extended controller offsets remain below. */
    case 0x6000: value = 0x44445201; break;
    case 0x6004: value = s->ddr_status; break;
    case 0x6008: value = s->ddr_error; break;
    case 0x600c: value = 0; break;
    case 0x6030: value = s->ddr_error; break;
    case 0x6038: value = 0x44440301; break;
    case 0x6200: value = s->ddr_perf_reads; break;
    case 0x6204: value = s->ddr_perf_writes; break;
    default: break;
    }
    if (off >= 0x5020 && off < 0x51c0) {
        uint32_t qoff = off - 0x5020;
        if (qoff == 0x000) value = s->qspi_ctrl;
        else if (qoff == 0x004) {
            value = s->qspi_status | (s->qspi_rx_count ? 0 : (1U << 1));
            if (s->qspi_tx_count >= 32) value |= 1U << 2;
            if (s->qspi_status & 1) {
                if (s->qspi_busy_polls && --s->qspi_busy_polls == 0)
                    soc_ref_qspi_complete(s, false, 0);
            }
        } else if (qoff == 0x008) value = s->qspi_clk_div;
        else if (qoff == 0x00c) value = s->qspi_cs_ctrl;
        else if (qoff == 0x010) value = s->qspi_irq_en;
        else if (qoff == 0x014) value = s->qspi_irq_status;
        else if (qoff == 0x018) value = s->qspi_timeout_limit;
        else if (qoff >= 0x020 && qoff < 0x040)
            value = s->qspi_lut[(qoff - 0x020) >> 2];
        else if (qoff == 0x044) value = 0;
        else if (qoff == 0x104) value = s->qspi_cmd_addr;
        else if (qoff == 0x108) value = s->qspi_cmd_len;
        else if (qoff == 0x114) {
            value = s->qspi_rx_count ? s->qspi_rx_fifo[s->qspi_rx_head] : 0;
            if (s->qspi_rx_count) {
                s->qspi_rx_head = (s->qspi_rx_head + 1) & 31;
                s->qspi_rx_count--;
            }
        } else if (qoff == 0x118)
            value = (s->qspi_rx_count << 8) | s->qspi_tx_count;
    }
    if (off >= 0x4100 && off < 0x4180)
        value = s->pic_priority[(off - 0x4100) >> 2] & 0xf;
    return value;
}

static void soc_ref_apb_write(void *opaque, hwaddr addr, uint64_t data,
                              unsigned size)
{
    MIPS32SocRefState *s = opaque;
    uint32_t off = addr & 0xffff;
    uint32_t value = data;
    if (off < 0x1000) { soc_ref_uart_write(s, off, data, size); return; }
    if ((off & 0xf000) == 0xa000 || (off & 0xf000) == 0xb000) {
        unsigned bank = ((off & 0xf000) == 0xb000) ? 1U : 0U;
        switch (off & 0xff) {
        case 0x20:
            s->ipi_target[bank] = value & 1U;
            s->ipi_generation[bank] = (value >> 8) & 0xffU;
            break;
        case 0x24: s->ipi_asid[bank] = value & 0xffU; break;
        case 0x28: s->ipi_vpn[bank] = value & 0xfffffU; break;
        case 0x2c: s->ipi_scope[bank] = value & 3U; break;
        case 0x30:
            if (value & 1U) soc_ref_ipi_send(s, bank);
            break;
        case 0x38: s->ipi_status[bank] &= ~(value & 0x3fU); break;
        case 0x3c: s->ipi_fault[bank] = value & 0xfU; break;
        default: break;
        }
        return;
    }
    if (off >= 0x3040 && off < 0x3140) {
        unsigned ch = (off - 0x3040) >> 6;
        unsigned reg = (off - 0x3040) & 0x3f;
        if (ch < 4) {
            switch (reg) {
            case 0x00:
                s->dma_v2_ctrl[ch] = value;
                if (value & 0x8) {
                    bool had_irq = (s->pic_raw & (1U << (3 + ch))) != 0;
                    s->dma_v2_status[ch] &= ~2U;
                    s->pic_raw &= ~(1U << (3 + ch));
                    soc_ref_dma_event(s, "W1C", ch, 0, 0, 0);
                    if (had_irq)
                        soc_ref_dma_event(s, "IRQ", ch, 0, 0, 0);
                }
                if (value & 0x10) {
                    s->dma_v2_status[ch] &= ~4U;
                    s->dma_v2_err_code[ch] = 0;
                    s->pic_raw &= ~(1U << (3 + ch));
                }
                soc_ref_update_irq(s);
                if (value & 0x1) {
                    s->dma_v2_status[ch] &= ~(1U | 2U | 4U);
                    soc_ref_dma_v2_start(s, ch);
                }
                break;
            case 0x04: if (!(s->dma_v2_status[ch] & 1)) s->dma_v2_src[ch] = value; break;
            case 0x08: if (!(s->dma_v2_status[ch] & 1)) s->dma_v2_dst[ch] = value; break;
            case 0x0c: if (!(s->dma_v2_status[ch] & 1)) s->dma_v2_len[ch] = value; break;
            case 0x10: if (!(s->dma_v2_status[ch] & 1)) s->dma_v2_desc_head[ch] = value; break;
            default: break;
            }
        }
        return;
    }
    switch (off) {
    case 0x9000:
        s->mmu_context_asid_generation = value;
        break;
    case 0x9004:
        s->mmu_context_vpn = value & 0x000fffffU;
        break;
    case 0x9008:
        s->mmu_context_scope = value & 0x3U;
        break;
    case 0x901c:
        if (value & 1U) {
            s->mmu_context_busy = true;
            s->mmu_context_invalidate_seen = true;
            s->mmu_context_status = 3U; /* busy + pending/invalidate */
        }
        break;
    case 0x9020:
        if (value & 1U) {
            s->mmu_context_invalidate_seen = true;
            if (s->mmu_context_busy) {
                /* ACK completes the one-target prototype transaction. */
                s->mmu_context_busy = false;
                /* RTL keeps the invalidate event sticky alongside DONE. */
                s->mmu_context_status = 6U; /* invalidate + done */
                /*
                 * The guest owns the architectural TLB.  A plain
                 * tlb_flush() only discards QEMU's translated shadow cache;
                 * it does not remove the architectural entry installed by
                 * the guest's TLBWR.  Mirror the RTL ASID-scope shootdown by
                 * invalidating matching non-global entries while retaining
                 * wired/global mappings.  The next access must therefore
                 * enter the guest software refill handler.
                 */
                CPUMIPSState *env = &s->cpu->env;
                uint32_t asid = s->mmu_context_asid_generation &
                                env->CP0_EntryHi_ASID_mask;
                if ((s->mmu_context_scope & 0x3U) == 1U) {
                    for (unsigned i = 0; i < env->tlb->nb_tlb; ++i) {
                        r4k_tlb_t *entry = &env->tlb->mmu.r4k.tlb[i];
                        if (!entry->EHINV && !entry->G && entry->ASID == asid)
                            entry->EHINV = 1;
                    }
                } else {
                    /* The current contract treats all other scopes as a
                     * complete dynamic-TLB flush; global entries remain
                     * usable only when the guest rewires them afterward. */
                    for (unsigned i = 0; i < env->tlb->nb_tlb; ++i) {
                        r4k_tlb_t *entry = &env->tlb->mmu.r4k.tlb[i];
                        if (!entry->EHINV && !entry->G)
                            entry->EHINV = 1;
                    }
                }
                tlb_flush(CPU(s->cpu));
            }
        }
        break;
    case 0x900c:
        s->mmu_context_event |= value & 0xfU;
        break;
    case 0x9010:
        s->mmu_context_event &= ~(value & 0xfU);
        break;
    case 0x9014:
        /* ASID-only allocation command. */
        if (value & 1U) {
            bool found = false;
            for (unsigned i = 0; i < 4; ++i) {
                if (!s->mmu_context_used[i] && !found) {
                    s->mmu_context_used[i] = true;
                    s->mmu_context_asid_generation =
                        ((uint32_t)s->mmu_context_generation[i] << 8) | (i + 1);
                    s->mmu_context_event |= 1U;
                    found = true;
                }
            }
            if (!found)
                s->mmu_context_event |= 2U;
        }
        break;
    case 0x9018:
        /* ASID-only release command. */
        if (value & 0x80000000U) {
            unsigned slot = (value & 0xffU);
            if (slot >= 1 && slot <= 4 &&
                s->mmu_context_used[slot - 1] &&
                s->mmu_context_generation[slot - 1] ==
                    ((value >> 8) & 0xffU)) {
                s->mmu_context_used[slot - 1] = false;
                s->mmu_context_generation[slot - 1]++;
                s->mmu_context_event |= 4U;
            } else {
                s->mmu_context_event |= 8U;
            }
        }
        break;
    case 0x902c:
        /* Root release payload holding register. */
        s->mmu_root_release_value = value;
        break;
    case 0x9034:
        /* ROOT_EVENT is write-one-to-set. */
        s->mmu_root_event |= value & 0xfU;
        break;
    case 0x9038:
        /* ROOT_EVENT_CLEAR is write-one-to-clear. */
        s->mmu_root_event &= ~(value & 0xfU);
        break;
    case 0x9028:
        /* Root allocation command; 0x9028 also reads the allocated root. */
        if (value & 1U) {
            bool found = false;
            for (unsigned i = 0; i < 4; ++i) {
                if (!s->mmu_root_used[i] && !found) {
                    s->mmu_root_used[i] = true;
                    s->mmu_root_value = 0x00100000U + i * 0x1000U;
                    s->mmu_root_value_generation = s->mmu_root_generation[i];
                    s->mmu_root_event |= 1U;
                    found = true;
                }
            }
            if (!found)
                s->mmu_root_event |= 2U;
        }
        break;
    case 0x9030:
        /* Root release command; the root address is held in 0x902c. */
        if (value & 0x80000000U) {
            unsigned slot = 4;
            for (unsigned i = 0; i < 4; ++i)
                if (s->mmu_root_release_value ==
                        0x00100000U + i * 0x1000U)
                    slot = i;
            if (slot < 4 && s->mmu_root_used[slot] &&
                s->mmu_root_generation[slot] == (value & 0xffU)) {
                s->mmu_root_used[slot] = false;
                s->mmu_root_generation[slot]++;
                s->mmu_root_event |= 4U;
            } else {
                s->mmu_root_event |= 8U;
            }
        }
        break;
    case 0x903c:
        /* Atomic context release+allocate, matching mmu_context_allocator's
         * slot selection and generation transition. */
        {
            unsigned release_slot = 4;
            bool release_match = false;
            uint8_t release_asid = value & 0xffU;
            uint8_t release_generation = (value >> 8) & 0xffU;
            if (value & 0x80000000U) {
                for (unsigned i = 0; i < 4; ++i)
                    if (s->mmu_root_release_value ==
                            0x00100000U + i * 0x1000U &&
                        release_asid == i + 1 &&
                        s->mmu_context_used[i] &&
                        s->mmu_context_generation[i] == release_generation)
                        release_slot = i;
                if (release_slot < 4) {
                    release_match = true;
                    s->mmu_context_used[release_slot] = false;
                    s->mmu_context_generation[release_slot]++;
                    s->mmu_context_event |= 4U;
                    s->mmu_root_event |= 4U;
                } else {
                    s->mmu_context_event |= 8U;
                    s->mmu_root_event |= 8U;
                }
            }
            if (value & 1U) {
                bool found = false;
                for (unsigned i = 0; i < 4; ++i) {
                    if ((!s->mmu_context_used[i] ||
                         (release_match && release_slot == i)) && !found) {
                        uint8_t generation = s->mmu_context_generation[i];
                        if (release_match && release_slot == i)
                            generation++;
                        s->mmu_context_used[i] = true;
                        s->mmu_context_asid_generation =
                            ((uint32_t)generation << 8) | (i + 1);
                        s->mmu_context_root_value = 0x00100000U + i * 0x1000U;
                        s->mmu_root_value = s->mmu_context_root_value;
                        s->mmu_root_value_generation = generation;
                        s->mmu_context_event |= 1U;
                        s->mmu_root_event |= 1U;
                        found = true;
                    }
                }
                if (!found) {
                    s->mmu_context_event |= 2U;
                    s->mmu_root_event |= 2U;
                }
            }
        }
        break;
    case 0x9040:
        /* Page-frame allocation command; first free slot wins, matching RTL. */
        if (value & 1U) {
            bool found = false;
            for (unsigned i = 0; i < 16; ++i) {
                if (!s->mmu_page_used[i] && !found) {
                    s->mmu_page_used[i] = true;
                    s->mmu_page_value = 0x00006000U + i * 0x1000U;
                    s->mmu_page_value_generation = s->mmu_page_generation[i];
                    s->mmu_page_event |= 1U;
                    found = true;
                }
            }
            if (!found)
                s->mmu_page_event |= 2U;
        }
        break;
    case 0x9044:
        /* Holding register for the physical page released through 0x9048. */
        s->mmu_page_release_value = value;
        break;
    case 0x9048:
        if (value & 0x80000000U) {
            unsigned slot = 16;
            for (unsigned i = 0; i < 16; ++i)
                if (s->mmu_page_release_value == 0x00006000U + i * 0x1000U)
                    slot = i;
            if (slot < 16 && s->mmu_page_used[slot] &&
                s->mmu_page_generation[slot] == (value & 0xffU)) {
                s->mmu_page_used[slot] = false;
                s->mmu_page_generation[slot]++;
                s->mmu_page_event |= 4U;
            } else {
                s->mmu_page_event |= 8U;
            }
        }
        break;
    case 0x904c:
        s->mmu_page_event |= value & 0xfU;
        break;
    case 0x9050:
        s->mmu_page_event &= ~(value & 0xfU);
        break;
    case 0x1000:
        if ((s->timer_ctrl & 1U) && !(value & 1U))
            /* RTL retains the current counter when it is disabled. */
            (void)soc_ref_timer_value(s);
        s->timer_ctrl = value;
        if (!(value & 1)) {
            s->timer_deadline = 0;
            timer_del(s->timer);
        } else if (s->timer_load) {
            uint32_t start_value = s->timer_value ? s->timer_value :
                                                    s->timer_load;
            s->timer_deadline = qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL) +
                                 (uint64_t)start_value * 20;
            timer_mod(s->timer, s->timer_deadline);
        }
        soc_ref_update_irq(s);
        break;
    case 0x1004:
        s->timer_load = value;
        /* RTL LOAD also initializes the current counter value. */
        s->timer_value = value;
        s->timer_deadline = qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL) +
                            (uint64_t)value * 20;
        if (s->timer_ctrl & 1)
            timer_mod(s->timer, s->timer_deadline);
        break;
    case 0x1008:
        /* TMR_VAL is a writable countdown register in the RTL. Preserve the
         * programmed value while stopped and schedule from that value when
         * the timer is running. */
        s->timer_value = value;
        s->timer_deadline = qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL) +
                            (uint64_t)value * 20;
        if (s->timer_ctrl & 1)
            timer_mod(s->timer, s->timer_deadline);
        break;
    case 0x100c:
        if (value & 1) {
            s->timer_int = 0;
            s->pic_raw &= ~(1U << 2);
            soc_ref_update_irq(s);
        }
        break;
    case 0x7000:
        if (!s->wdt_lock) {
            s->wdt_ctrl = value & 1U;
            if (value & 2U)
                s->wdt_lock = true;
            if (s->wdt_ctrl & 1U) {
                s->wdt_value = s->wdt_load;
                timer_mod(s->wdt_timer,
                          qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL) +
                          (uint64_t)s->wdt_load * 20);
            } else {
                s->wdt_value = 0;
                timer_del(s->wdt_timer);
            }
        }
        break;
    case 0x7004:
        if (!s->wdt_lock)
            s->wdt_load = value;
        break;
    case 0x700c:
        if (value == 0x1acce551U && (s->wdt_ctrl & 1U)) {
            s->wdt_value = s->wdt_load;
            timer_mod(s->wdt_timer,
                      qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL) +
                      (uint64_t)s->wdt_load * 20);
        }
        break;
    case 0x7010:
        if (value & 1U)
            s->wdt_expired = false;
        break;
    case 0x8000: s->boot_stage = value & 0xffU; break;
    case 0x8004: s->boot_failure = value; break;
    case 0x8008: s->boot_reset_cause &= ~(value & 3U); break;
    case 0x2000: s->gpio_data = value; break;
    case 0x2004: s->gpio_dir = value; break;
    case 0x3000: s->dma_src = value; break;
    case 0x3004: s->dma_dst = value; break;
    case 0x3008: s->dma_len = value; break;
    case 0x300c:
        s->dma_ctrl = value;
        if (value & 4) {
            s->dma_status &= ~4U; /* DONE W1C */
            soc_ref_dma_event_legacy(s, "W1C", 0, 0);
            if (s->dma_ctrl & 2) {
                s->pic_raw &= ~4U;
                soc_ref_update_irq(s);
                soc_ref_dma_event(s, "IRQ", 0, 0, 0, 0);
            }
        }
        if (value & 1) soc_ref_dma_start(s);
        break;
    case 0x4004: s->pic_mask = value; soc_ref_update_irq(s); break;
    case 0x400c: s->pic_mask |= value; soc_ref_update_irq(s); break;
    case 0x4010: s->pic_mask &= ~value; soc_ref_update_irq(s); break;
    case 0x4014: s->pic_type = value; break;
    case 0x4018: s->pic_polarity = value; break;
    case 0x401c: s->pic_soft |= value; soc_ref_update_irq(s); break;
    case 0x4020: s->pic_soft &= ~value; soc_ref_update_irq(s); break;
    case 0x4208:
        s->pic_active &= ~value;
        s->pic_soft &= ~value;
        if (s->irq_replay_enabled)
            qemu_set_irq(s->cpu->env.irq[2], false);
        soc_ref_update_irq(s);
        break;
    case 0x500c: if (value & 1) s->qspi_timeout = 0; break;
    case 0x600c:
        if (value & 1) {
            s->ddr_error = 0;
            s->ddr_status &= ~(1U << 5);
        }
        break;
    case 0x6034:
        if (value & 1) {
            s->ddr_error = 0;
            s->ddr_status &= ~(1U << 5);
        }
        break;
    }
    if (off >= 0x5020 && off < 0x51c0) {
        uint32_t qoff = off - 0x5020;
        if (qoff == 0x000) {
            s->qspi_ctrl = value & 0xfffffff9U;
            if (value & 2) soc_ref_qspi_clear(s);
            if (!(value & 1) && (s->qspi_status & 1)) {
                s->qspi_status &= ~1U;
                s->qspi_status |= (1U << 4) | (1U << 6) | (1U << 3);
                s->qspi_irq_status |= 5;
            }
            if (value & 4) {
                s->qspi_status &= ~1U;
                s->qspi_status |= (1U << 4) | (1U << 6) | (1U << 3);
                s->qspi_irq_status |= 5;
            }
        } else if (qoff == 0x008) s->qspi_clk_div = value;
        else if (qoff == 0x00c) s->qspi_cs_ctrl = value;
        else if (qoff == 0x010) s->qspi_irq_en = value;
        else if (qoff == 0x014) {
            if (value & 1) s->qspi_irq_status &= ~1U;
            if (value & 2) s->qspi_irq_status &= ~2U;
            if (value & 4) s->qspi_irq_status &= ~4U;
            if (value & 1) s->qspi_status &= ~(1U << 3);
            if (value & 2) s->qspi_status &= ~(1U << 5);
            if (value & 4) s->qspi_status &= ~(1U << 6);
            if (value & 1) s->pic_raw &= ~(1U << 4);
            soc_ref_update_irq(s);
        } else if (qoff == 0x018) s->qspi_timeout_limit = value;
        else if (qoff >= 0x020 && qoff < 0x040)
            s->qspi_lut[(qoff - 0x020) >> 2] = value;
        else if (qoff == 0x100) soc_ref_qspi_start(s, value);
        else if (qoff == 0x104) s->qspi_cmd_addr = value;
        else if (qoff == 0x108) s->qspi_cmd_len = value & 0xffff;
        else if (qoff == 0x110 && s->qspi_tx_count < 32) {
            s->qspi_tx_fifo[s->qspi_tx_tail] = value;
            s->qspi_tx_tail = (s->qspi_tx_tail + 1) & 31;
            s->qspi_tx_count++;
        }
    }
    if (off >= 0x4100 && off < 0x4180)
        s->pic_priority[(off - 0x4100) >> 2] = value & 0xf;
}

static const MemoryRegionOps soc_ref_apb_ops = {
    .read = soc_ref_apb_read, .write = soc_ref_apb_write,
    .endianness = DEVICE_LITTLE_ENDIAN,
    .valid = { .min_access_size = 1, .max_access_size = 4 },
};

static void soc_ref_cpu_reset(void *opaque)
{
    MIPS32SocRefResetData *reset = opaque;
    CPUMIPSState *env = &reset->cpu->env;

    cpu_reset(CPU(reset->cpu));
    /* SRAM-linked software-MMU guests place their general exception handler
     * at EBase+0x180. Boot-ROM guests keep BEV set for BFC00200. */
    if (reset->software_mmu_guest &&
        !soc_ref_software_mmu_bootrom_guest) {
        env->CP0_Status &= ~(1U << CP0St_BEV);
    }
    /* Match the opt-in RTL SRSCtl static HSS field.  CSS/PSS/ESS remain
     * software and exception controlled below this implementation. */
    env->CP0_SRSCtl = soc_ref_rtl_cp0_identity ? 0U : (0xfU << 23);
    env->active_tc.PC = reset->vector & ~(target_ulong)1;
    if (reset->vector & 1) {
        env->hflags |= MIPS_HFLAG_M16;
    }

    /* The 24Kf model exposes an FPU, but its system-mode Status write mask
     * does not retain CU1 for this bare-metal machine.  Keep CU1 clear at
     * reset so the negative COP1 gate remains meaningful, while allowing the
     * guest's normal MTC0 Status sequence to enable COP1. */
    env->CP0_Status_rw_bitmask |= (1U << CP0St_CU1);

    /* The RTL exposes EBase.WG (bit 11) as writable.  QEMU CPU models vary
     * in this mask; make the behavior explicit for the opt-in differential
     * identity so Linux's EBase capability probe follows the RTL contract. */
    if (soc_ref_rtl_cp0_identity) {
        env->CP0_EBaseWG_rw_bitmask |= (1U << CP0EBase_WG);
    }

    /* The differential property selects the exact RTL CP0 identity. Generic
     * UHI/Linux remains on QEMU's native Config1..3 contract so its existing
     * userspace workload remains independent of the RTL cache geometry. */
    if (!reset->fdt_loaded || soc_ref_rtl_cp0_identity) {
        /* Match the RTL's fixed custom AP-lite processor identity. */
        env->CP0_PRid = 0x00019300;
        env->CP0_Config0 = 0x80000503;
        if (!reset->fdt_loaded || soc_ref_rtl_cp0_identity) {
            /* Bare-metal guests and RTL differential Linux guests match the
             * RTL cache/MMU geometry. */
            env->CP0_Config1 = 0xFE231180;
            if (reset->cpu_has_fpu) {
                /* COP1 availability is controlled by Status.CU1 after reset. */
                env->CP0_Config1 |= (1U << CP0C1_FP);
            }
            env->CP0_Config2 = 0x80000000;
            env->CP0_Config3 = 0x00002008;
        }
        /* Match the RTL CP0 timer reset contract. QEMU's generic MIPS
         * reset leaves Compare at its reset value, which can set Cause.TI
         * during a short differential corpus and expose an unrelated IP7
         * bit in MFC0 Cause reads. */
        if (env->timer) {
            cpu_mips_store_count(env, 0);
            env->CP0_Compare = UINT32_MAX;
            env->CP0_Cause &= ~(1U << CP0Ca_TI);
        } else {
            /* cpu_mips_clock_init() has not run on the earliest reset path. */
            env->CP0_Count = 0;
            env->CP0_Compare = UINT32_MAX;
            env->CP0_Cause &= ~(1U << CP0Ca_TI);
        }
        /* A generic MIPS reset can leave an already-raised timer IRQ line
         * behind even after the Cause.TI bit is cleared.  The RTL reset has
         * no pending hardware interrupt, so clear every line before the
         * guest starts. */
        for (int irq = 0; irq < 8; ++irq) {
            qemu_set_irq(env->irq[irq], false);
        }
    }

    if (reset->fdt_loaded) {
        /* Linux generic MIPS consumes the UHI FDT contract before C code:
         * a0=-2 identifies UHI and a1 is the kseg0 virtual FDT address. */
        env->active_tc.gpr[4] = (target_ulong)-2;
        env->active_tc.gpr[5] = reset->fdt_addr;
        env->active_tc.gpr[6] = reset->rng_env_addr;
        env->active_tc.gpr[7] = 0;
        if (soc_ref_rtl_cp0_identity) {
            /* The RTL Boot ROM writes EBase through $t1 and retains it at
             * the ELF handoff; QEMU starts directly at that handoff. */
            env->active_tc.gpr[9] = 0x80000000;
        }
    }

    if (!reset->software_mmu_guest && !reset->fdt_loaded) {
        /* Bare-metal prototype guests use fixed identity mappings. Linux
         * owns the TLB after the DTB/UHI handoff and must start with no
         * prototype wired entries competing with its page-table refill path. */
        env->CP0_Index = 0;
        env->CP0_PageMask = 0x0007e000; /* 256-KB pages, 512-KB pair */
        env->CP0_EntryHi = 0;
        env->CP0_EntryLo0 = 0x0000001f; /* PA 0, G/V/D, uncached */
        env->CP0_EntryLo1 = 0x0000101f; /* PA 0x40000 */
        env->tlb->helper_tlbwi(env);

        env->CP0_Index = 1;
        /* The APB contract is a 64-KB window; map both halves of the page pair. */
        env->CP0_PageMask = 0x0001e000;
        env->CP0_EntryHi = 0x40000000;
        env->CP0_EntryLo0 = 0x0100001f; /* PA 0x40000000 */
        env->CP0_EntryLo1 = 0x0100041f; /* PA 0x40010000 */
        env->tlb->helper_tlbwi(env);

        /* Map the vendor-neutral flash XIP and DDR windows used by RTL. */
        env->CP0_Index = 2;
        env->CP0_PageMask = 0x0001e000;
        env->CP0_EntryHi = 0x10000000;
        env->CP0_EntryLo0 = 0x0040001f; /* PA 0x10000000 */
        env->CP0_EntryLo1 = 0x0040101f; /* PA 0x10040000 */
        env->tlb->helper_tlbwi(env);

        env->CP0_Index = 3;
        env->CP0_PageMask = 0x0001e000;
        env->CP0_EntryHi = 0x08000000;
        env->CP0_EntryLo0 = 0x0020001f; /* PA 0x08000000 */
        env->CP0_EntryLo1 = 0x0020101f; /* PA 0x08040000 */
        env->tlb->helper_tlbwi(env);
    }
}

static void mips32_soc_ref_init(MachineState *machine)
{
    MemoryRegion *system_memory = get_system_memory();
    MemoryRegion *bootrom_alias = g_new(MemoryRegion, 1);
    MemoryRegion *sram_alias = g_new(MemoryRegion, 1);
    MemoryRegion *sram_kseg0 = g_new(MemoryRegion, 1);
    MIPS32SocRefState *state = g_new0(MIPS32SocRefState, 1);
    MIPS32SocRefResetData *reset;
    Clock *cpuclk;
    MIPSCPU *cpu;
    uint64_t entry = 0;
    hwaddr fdt_base = 0;
    g_autofree gchar *fdt_data = NULL;
    gsize fdt_size = 0;
    bool fdt_loaded = false;
    ssize_t image_size;

    if (machine->ram_size < SOC_SRAM_SIZE) {
        error_report("mips32-soc-ref requires at least 64 KiB of SRAM");
        exit(EXIT_FAILURE);
    }
    if (soc_ref_uart_modem_inputs & ~0x0fU) {
        error_report("uart-modem-inputs must be a four-bit active-low mask");
        exit(EXIT_FAILURE);
    }

    cpuclk = clock_new(OBJECT(machine), "cpu-refclk");
    clock_set_hz(cpuclk, 50 * 1000 * 1000);
    cpu = mips_cpu_create_with_clock(machine->cpu_type, cpuclk, false);
    state->cpu = cpu;
    state->uart_dll = 1;
    state->uart_dlm = 0;
    state->uart_diff_timing = soc_ref_uart_diff_timing;
    state->uart_regs[3] = 0x03;
    soc_ref_uart_modem_reset(&state->uart_modem,
                             (uint8_t)soc_ref_uart_modem_inputs);
    state->uart_tx_busy_reads = 0;
    state->uart_write_count = 0;
    state->uart_tx = (SocRefUartTxModel){0};
    state->irq_replay_pic_mask = soc_ref_irq_replay_pic_mask;
    state->irq_replay_bd_mask = soc_ref_irq_replay_bd_mask;
    state->sram = machine->ram;
    state->gpio_input = soc_ref_gpio_input;
    state->dma_fault_mode = soc_ref_dma_fault_mode;
    state->ddr_fault_mode = soc_ref_ddr_fault_mode;
    state->cp0_trace_interval = soc_ref_cp0_trace_interval;
    state->cp0_retire_clock = soc_ref_cp0_retire_clock;
    state->stop_on_terminal_marker = soc_ref_stop_on_terminal_marker;
    state->cp0_linux_timer_phase = SOC_REF_LINUX_TIMER_RESET;
    state->cp0_linux_timer_late_suppressed = true;
    soc_ref_load_irq_schedule(state);
    soc_ref_load_cp0_count_schedule(state);
    soc_ref_load_cp0_random_schedule(state);
    soc_ref_load_cpu_cycle_schedule(state);
    soc_ref_load_uart_apb_schedule(state);
    soc_ref_active_state = state;
    if (state->cp0_count_schedule) {
        atexit(soc_ref_report_cp0_count_schedule);
    }
    if (state->cp0_random_schedule) {
        atexit(soc_ref_report_cp0_random_schedule);
    }
    if (state->cpu_cycle_schedule) {
        atexit(soc_ref_report_cpu_cycle_schedule);
    }
    if (state->uart_apb_schedule) {
        atexit(soc_ref_report_uart_apb_schedule);
    }
    if (state->irq_release_after) {
        atexit(soc_ref_report_irq_schedule);
    }
    if (soc_ref_dma_event_trace_path) {
        state->dma_event_trace = fopen(soc_ref_dma_event_trace_path, "w");
        if (!state->dma_event_trace) {
            error_report("could not open DMA event trace '%s'", soc_ref_dma_event_trace_path);
            exit(EXIT_FAILURE);
        }
    }
    if (soc_ref_peripheral_trace_path) {
        state->peripheral_trace = fopen(soc_ref_peripheral_trace_path, "w");
        if (!state->peripheral_trace) {
            error_report("could not open peripheral trace '%s'",
                         soc_ref_peripheral_trace_path);
            exit(EXIT_FAILURE);
        }
    }
    if (soc_ref_cp0_trace_path) {
        state->cp0_trace = fopen(soc_ref_cp0_trace_path, "w");
        if (!state->cp0_trace) {
            error_report("could not open CP0 trace '%s'", soc_ref_cp0_trace_path);
            exit(EXIT_FAILURE);
        }
    }

    memory_region_add_subregion(system_memory, 0, machine->ram);
    memory_region_init_alias(sram_alias, NULL, "mips32-soc-ref.sram-kseg1",
                             machine->ram, 0, machine->ram_size);
    memory_region_add_subregion(system_memory, SOC_SRAM_ALIAS, sram_alias);
    memory_region_init_alias(sram_kseg0, NULL, "mips32-soc-ref.sram-kseg0",
                             machine->ram, 0, machine->ram_size);
    memory_region_add_subregion(system_memory, 0x80000000ULL, sram_kseg0);

    /* RTL product-MMU guests link their reset image at kseg1 BFC0_0000.
     * Keep a distinct physical BootROM window so those guests can execute
     * the same image under QEMU instead of falling into an unmapped reset
     * fetch.  The alias covers the CPU's uncached BFC address directly. */
    memory_region_init_ram(&state->bootrom, NULL,
                           "mips32-soc-ref.bootrom", SOC_BOOTROM_SIZE,
                           &error_fatal);
    if (soc_ref_malta_uboot_compat) {
        /* CONFIG_TARGET_MALTA probes this YAMON revision field before its
         * low-level board setup. The value selects the GT64120 path. */
        stl_le_p(memory_region_get_ram_ptr(&state->bootrom) + 0x10,
                 1U << 10);
    }
    memory_region_add_subregion(system_memory, SOC_BOOTROM_BASE,
                                &state->bootrom);
    memory_region_init_alias(bootrom_alias, NULL,
                             "mips32-soc-ref.bootrom-kseg1",
                             &state->bootrom, 0, SOC_BOOTROM_SIZE);
    memory_region_add_subregion(system_memory, 0xbfc00000ULL,
                                bootrom_alias);

    if (soc_ref_malta_uboot_compat) {
        /* Malta's GT64120 PCI I/O window is physical 0x18000000 and its
         * serial node is at +0x3f8. This alias is opt-in and deliberately
         * does not change the vendor-neutral SoC UART address. */
        memory_region_init_io(&state->malta_uart, NULL,
                              &soc_ref_malta_uart_ops, state,
                              "mips32-soc-ref.malta-uart", 0x40);
        memory_region_add_subregion_overlap(system_memory,
                                             0x180003f8ULL,
                                             &state->malta_uart, 2);
    }

    memory_region_init_io(&state->apb, NULL, &soc_ref_apb_ops, state,
                          "mips32-soc-ref.apb", SOC_APB_SIZE);
    /* The flash boot alias spans through 0x4fffffff.  Keep the SoC APB
     * window authoritative where those vendor-neutral physical ranges
     * overlap, including the MMU context mailbox at offset 0x9000. */
    memory_region_add_subregion_overlap(system_memory, SOC_APB_BASE,
                                        &state->apb, 3);
    /* Keep the UART as a first-class device endpoint. The APB region remains
     * the owner of all other CSRs, while this higher-priority subregion makes
     * the console path explicit for both cached and MMU-translated guests. */
    memory_region_init_io(&state->uart, NULL, &soc_ref_uart_ops, state,
                          "mips32-soc-ref.uart", SOC_UART_SIZE);
    memory_region_add_subregion_overlap(system_memory, SOC_UART_BASE,
                                        &state->uart, 1);
    memory_region_init_io(&state->dma_legacy, NULL, &soc_ref_dma_legacy_ops,
                          state, "mips32-soc-ref.dma-legacy", 0x10);
    memory_region_add_subregion_overlap(system_memory, SOC_APB_BASE + 0x3000,
                                        &state->dma_legacy, 1);
    memory_region_init_io(&state->dma_v2_window, NULL, &soc_ref_dma_v2_ops,
                          state, "mips32-soc-ref.dma-v2-window", 0x100);
    memory_region_add_subregion_overlap(system_memory, SOC_APB_BASE + 0x3040,
                                        &state->dma_v2_window, 1);
    /* The flash boot alias overlaps the APB range at equal priority. Keep
     * the complete VIC CSR span explicit so priority and VEC/ACK registers
     * cannot be decoded as flash-backed RAM. */
    memory_region_init_io(&state->pic_window, NULL, &soc_ref_pic_ops, state,
                          "mips32-soc-ref.pic-window", 0x240);
    memory_region_add_subregion_overlap(system_memory, SOC_APB_BASE + 0x4000,
                                        &state->pic_window, 1);
    memory_region_init_io(&state->qspi_window, NULL, &soc_ref_qspi_ops,
                          state, "mips32-soc-ref.qspi-window", 0x200);
    memory_region_add_subregion_overlap(system_memory, SOC_APB_BASE + 0x5000,
                                        &state->qspi_window, 1);
    memory_region_init_io(&state->ddr_status_window, NULL,
                          &soc_ref_ddr_status_ops, state,
                          "mips32-soc-ref.ddr-status-window", 0x100);
    memory_region_add_subregion_overlap(system_memory, SOC_APB_BASE + 0x6000,
                                        &state->ddr_status_window, 1);
    /* Keep both IPI mailbox CSRs as explicit windows. This mirrors the RTL's
     * separate APB selects and makes the sparse 0xA000/0xB000 decode visible
     * even when the parent APB region is backed by an alias. */
    memory_region_init_io(&state->ipi_window[0], NULL, &soc_ref_ipi_ops,
                          (void *)(uintptr_t)0,
                          "mips32-soc-ref.ipi-core0-window", 0x40);
    memory_region_add_subregion_overlap(system_memory, SOC_APB_BASE + 0xa000,
                                        &state->ipi_window[0], 2);
    memory_region_init_io(&state->ipi_window[1], NULL, &soc_ref_ipi_ops,
                          (void *)(uintptr_t)1,
                          "mips32-soc-ref.ipi-core1-window", 0x40);
    memory_region_add_subregion_overlap(system_memory, SOC_APB_BASE + 0xb000,
                                        &state->ipi_window[1], 2);
    /* The RTL product-MMU firmware uses the prototype PFN encoding
     * 0x01000217 for its C000_9000 wired mapping.  Under standard MIPS
     * EntryLo decoding that resolves to physical 0x0400_0000, while the
     * non-MMU APB contract is exposed at 0x4000_0000.  Keep both physical
     * aliases in the reference machine so the same firmware is executable
     * under QEMU without changing the RTL contract. */
    memory_region_init_alias(&state->apb_mmu_alias, NULL,
                             "mips32-soc-ref.apb-mmu-alias", &state->apb,
                             0, SOC_APB_SIZE);
    memory_region_add_subregion(system_memory, 0x04000000ULL,
                                &state->apb_mmu_alias);
    /* Do not add a second full-size alias at 0x04001000: it would overlap
     * the first 64KB window and remap 0x04009024 as APB offset 0x8024. */
    /* 0x7000 and 0x8000 are real physical SRAM addresses.  Do not overlay
     * them with the APB WDT/boot-status windows: the QEMU WDT contract uses
     * the architecturally mapped uncached APB aliases (0xa0007000 and
     * 0xa0008000), and low aliases would corrupt ordinary SRAM workloads. */
    memory_region_init_alias(&state->uart_mmu_alias, NULL,
                             "mips32-soc-ref.uart-mmu-alias", &state->uart,
                             0, SOC_UART_SIZE);
    memory_region_add_subregion_overlap(system_memory, 0x04000000ULL,
                                        &state->uart_mmu_alias, 1);
    memory_region_init_alias(&state->uart_mmu_odd_alias, NULL,
                             "mips32-soc-ref.uart-mmu-odd-alias", &state->uart,
                             0, SOC_UART_SIZE);
    memory_region_add_subregion_overlap(system_memory, 0x04001000ULL,
                                        &state->uart_mmu_odd_alias, 1);

    memory_region_init_ram(&state->ddr, NULL,
                           "mips32-soc-ref.ddr", SOC_DDR_SIZE, &error_fatal);
    memory_region_add_subregion(system_memory, SOC_DDR_BASE, &state->ddr);
    memory_region_init_ram(&state->flash, NULL,
                           "mips32-soc-ref.flash", SOC_FLASH_SIZE, &error_fatal);
    memory_region_add_subregion(system_memory, SOC_FLASH_BASE, &state->flash);
    /* MIPS kseg1 execution of ROM-resident images such as U-Boot uses
     * virtual 0xbe000000, which the ELF loader translates to physical
     * 0x3e000000. Keep the vendor-neutral XIP window and the boot alias
     * backed by the same flash contents so image loading and CPU fetches
     * observe one architectural image. */
    memory_region_init_alias(&state->flash_boot_alias, NULL,
                             "mips32-soc-ref.flash-kseg1-boot",
                             &state->flash, 0, SOC_FLASH_SIZE);
    memory_region_add_subregion(system_memory, 0x3e000000ULL,
                                &state->flash_boot_alias);
    if (soc_ref_qspi_image) {
        g_autofree gchar *image = NULL;
        gsize qspi_size = 0;
        if (!g_file_get_contents(soc_ref_qspi_image, &image, &qspi_size,
                                 NULL)) {
            error_report("could not load QSPI image '%s'", soc_ref_qspi_image);
            exit(EXIT_FAILURE);
        }
        if (qspi_size > SOC_FLASH_SIZE) {
            error_report("QSPI image '%s' exceeds 256 MiB", soc_ref_qspi_image);
            exit(EXIT_FAILURE);
        }
        memcpy(memory_region_get_ram_ptr(&state->flash), image, qspi_size);
    }

    memory_region_init_io(&state->mailbox, NULL, &soc_ref_mailbox_ops, state,
                          "mips32-soc-ref.mailbox", sizeof(uint32_t));
    /* kseg1 A000_FFFC translates to physical 0000_FFFC in QEMU. */
    memory_region_add_subregion_overlap(system_memory, 0x0000fffcULL,
                                        &state->mailbox, 1);

    state->timer = timer_new_ns(QEMU_CLOCK_VIRTUAL, soc_ref_timer_cb, state);
    state->wdt_timer = timer_new_ns(QEMU_CLOCK_VIRTUAL, soc_ref_wdt_cb, state);
    state->wdt_load = UINT32_MAX;
    state->boot_reset_cause = 1U; /* POR */
    state->pic_mask = 0;
    soc_ref_qspi_clear(state);
    /* controller_present + init_done + training_done */
    state->ddr_status = 7;
    if (state->ddr_fault_mode) {
        state->ddr_status |= 1U << 5;
        state->ddr_error = state->ddr_fault_mode == 1 ?
                          0x00040004U : 0x00040005U;
    }

    if (machine->kernel_filename) {
        image_size = load_elf(machine->kernel_filename, NULL,
                              cpu_mips_kseg0_to_phys, NULL,
                              &entry, NULL, NULL, NULL,
                              0, EM_MIPS, 1, 0);
        if (image_size < 0) {
            error_report("could not load firmware '%s': %s",
                         machine->kernel_filename,
                         load_elf_strerror(image_size));
            exit(EXIT_FAILURE);
        }
    }

    if (machine->dtb) {
        if (!g_file_get_contents(machine->dtb, &fdt_data, &fdt_size,
                                 NULL)) {
            error_report("could not load DTB '%s'", machine->dtb);
            exit(EXIT_FAILURE);
        }
        if (fdt_size == 0 || fdt_size > SOC_FDT_MAX_SIZE) {
            error_report("DTB '%s' must be between 1 and %zu bytes",
                         machine->dtb, (size_t)SOC_FDT_MAX_SIZE);
            exit(EXIT_FAILURE);
        }
        /* Keep the Linux handoff identical to the RTL image builder. The
         * prototype DDR contract places the DTB at physical 0x09f00000,
         * which Linux receives through the kseg0 alias as 0x89f00000. Do not
         * derive this from -m: the RTL DDR window and the QEMU machine RAM
         * size are intentionally separate implementation details. */
        if (machine->ram_size < (2 * MiB)) {
            error_report("-dtb requires at least 2 MiB of guest RAM");
            exit(EXIT_FAILURE);
        }
        fdt_base = SOC_LINUX_FDT_BASE;
        if (address_space_write(&address_space_memory, fdt_base,
                                MEMTXATTRS_UNSPECIFIED, (uint8_t *)fdt_data,
                                fdt_size) != MEMTX_OK) {
            error_report("could not place DTB '%s' at 0x%" HWADDR_PRIx,
                         machine->dtb, fdt_base);
            exit(EXIT_FAILURE);
        }
        fdt_loaded = true;
    }

    reset = g_new0(MIPS32SocRefResetData, 1);
    reset->cpu = cpu;
    reset->fdt_addr = fdt_loaded ?
                      cpu_mips_phys_to_kseg0(NULL, fdt_base) : 0;
    reset->rng_env_addr = soc_ref_write_linux_rng_env();
    reset->fdt_loaded = fdt_loaded;
    reset->cpu_has_fpu = (cpu->env.CP0_Config1 & (1U << CP0C1_FP)) != 0;
    /* ELF payloads and RTL reset both start in kuseg at the physical entry.
     * soc_ref_cpu_reset installs the matching identity TLB entry before the
     * first fetch, avoiding a kseg0-only link-address alias in retire traces. */
    reset->vector = entry;
    reset->software_mmu_guest = soc_ref_software_mmu_guest ||
                                (entry == 0xbfc00000ULL);
    qemu_register_reset(soc_ref_cpu_reset, reset);
    qemu_register_reset(soc_ref_wdt_reset, state);
    qemu_register_reset(soc_ref_dma_reset, state);

    cpu_mips_irq_init_cpu(cpu);
    cpu_mips_clock_init(cpu);
}

static void mips32_soc_ref_machine_init(MachineClass *mc)
{
    mc->desc = "Project MIPS32 SoC reference machine";
    mc->init = mips32_soc_ref_init;
    /* The RTL default is integer-only; FPU differential gates select 24Kf
     * explicitly through -cpu. */
    mc->default_cpu_type = MIPS_CPU_TYPE_NAME("24Kc");
    mc->default_ram_size = SOC_SRAM_SIZE;
    mc->default_ram_id = "mips32-soc-ref.sram";
    object_class_property_add_str(OBJECT_CLASS(mc), "qspi-image",
                                  soc_ref_get_qspi_image,
                                  soc_ref_set_qspi_image);
    object_class_property_add_str(OBJECT_CLASS(mc), "linux-rng-seed",
                                  soc_ref_get_linux_rng_seed,
                                  soc_ref_set_linux_rng_seed);
    object_class_property_add_bool(OBJECT_CLASS(mc), "malta-u-boot-compat",
                                   soc_ref_get_malta_uboot_compat,
                                   soc_ref_set_malta_uboot_compat);
    object_class_property_add_bool(OBJECT_CLASS(mc), "linux-guest",
                                   soc_ref_get_linux_guest,
                                   soc_ref_set_linux_guest);
    object_class_property_add_bool(OBJECT_CLASS(mc), "rtl-cp0-identity",
                                   soc_ref_get_rtl_cp0_identity,
                                   soc_ref_set_rtl_cp0_identity);
    object_class_property_add_bool(OBJECT_CLASS(mc), "cp0-retire-clock",
                                   soc_ref_get_cp0_retire_clock,
                                   soc_ref_set_cp0_retire_clock);
    object_class_property_add_bool(
        OBJECT_CLASS(mc), "stop-on-terminal-marker",
        soc_ref_get_stop_on_terminal_marker,
        soc_ref_set_stop_on_terminal_marker);
    object_class_property_add_str(OBJECT_CLASS(mc), "irq-schedule",
                                  soc_ref_get_irq_schedule,
                                  soc_ref_set_irq_schedule);
    object_class_property_add_str(OBJECT_CLASS(mc), "cp0-count-schedule",
                                  soc_ref_get_cp0_count_schedule,
                                  soc_ref_set_cp0_count_schedule);
    object_class_property_add_str(OBJECT_CLASS(mc), "cp0-random-schedule",
                                  soc_ref_get_cp0_random_schedule,
                                  soc_ref_set_cp0_random_schedule);
    object_class_property_add_str(OBJECT_CLASS(mc), "cpu-cycle-schedule",
                                  soc_ref_get_cpu_cycle_schedule,
                                  soc_ref_set_cpu_cycle_schedule);
    object_class_property_add_str(OBJECT_CLASS(mc), "uart-apb-schedule",
                                  soc_ref_get_uart_apb_schedule,
                                  soc_ref_set_uart_apb_schedule);
    object_class_property_add_bool(
        OBJECT_CLASS(mc), "uart-apb-schedule-diagnostic-continue",
        soc_ref_get_uart_apb_schedule_diagnostic_continue,
        soc_ref_set_uart_apb_schedule_diagnostic_continue);
    object_class_property_add_bool(OBJECT_CLASS(mc), "uart-diff-timing",
                                   soc_ref_get_uart_diff_timing,
                                   soc_ref_set_uart_diff_timing);
    object_class_property_add_uint32_ptr(OBJECT_CLASS(mc),
                                         "irq-replay-pic-mask",
                                         &soc_ref_irq_replay_pic_mask,
                                         OBJ_PROP_FLAG_WRITE);
    object_class_property_add_uint32_ptr(OBJECT_CLASS(mc),
                                         "irq-replay-bd-mask",
                                         &soc_ref_irq_replay_bd_mask,
                                         OBJ_PROP_FLAG_WRITE);
    object_class_property_add_str(OBJECT_CLASS(mc), "dma-event-trace",
                                  soc_ref_get_dma_event_trace,
                                  soc_ref_set_dma_event_trace);
    object_class_property_add_str(OBJECT_CLASS(mc), "peripheral-trace",
                                  soc_ref_get_peripheral_trace,
                                  soc_ref_set_peripheral_trace);
    object_class_property_add_str(OBJECT_CLASS(mc), "cp0-trace",
                                  soc_ref_get_cp0_trace,
                                  soc_ref_set_cp0_trace);
    object_class_property_add_uint32_ptr(OBJECT_CLASS(mc), "cp0-trace-interval",
                                         &soc_ref_cp0_trace_interval,
                                         OBJ_PROP_FLAG_WRITE);
    object_class_property_add_uint32_ptr(OBJECT_CLASS(mc), "dma-fault-mode",
                                         &soc_ref_dma_fault_mode,
                                         OBJ_PROP_FLAG_WRITE);
    object_class_property_add_bool(OBJECT_CLASS(mc), "dma-reset-inflight",
                                   soc_ref_get_dma_reset_inflight,
                                   soc_ref_set_dma_reset_inflight);
    object_class_property_add_uint32_ptr(OBJECT_CLASS(mc), "gpio-input",
                                         &soc_ref_gpio_input,
                                         OBJ_PROP_FLAG_WRITE);
    object_class_property_add_uint32_ptr(OBJECT_CLASS(mc),
                                         "uart-modem-inputs",
                                         &soc_ref_uart_modem_inputs,
                                         OBJ_PROP_FLAG_WRITE);
    object_class_property_add_uint32_ptr(OBJECT_CLASS(mc), "ddr-fault-mode",
                                         &soc_ref_ddr_fault_mode,
                                         OBJ_PROP_FLAG_WRITE);
    object_class_property_add_bool(OBJECT_CLASS(mc), "software-mmu-guest",
                                   soc_ref_get_software_mmu_guest,
                                   soc_ref_set_software_mmu_guest);
    object_class_property_add_bool(OBJECT_CLASS(mc),
                                   "software-mmu-bootrom-guest",
                                   soc_ref_get_software_mmu_bootrom_guest,
                                   soc_ref_set_software_mmu_bootrom_guest);
    mc->max_cpus = 1;
};

DEFINE_MACHINE("mips32-soc-ref", mips32_soc_ref_machine_init)
