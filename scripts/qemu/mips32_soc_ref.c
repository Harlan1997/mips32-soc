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

/* The RTL CP0 contract exposes LLAddr as the aligned virtual address. */
bool qemu_mips32_soc_ref_lladdr_virtual(void)
{
    return true;
}

#define SOC_SRAM_SIZE      (64 * KiB)
#define SOC_BOOTROM_BASE   0x1fc00000ULL
#define SOC_BOOTROM_SIZE   (64 * KiB)
#define SOC_SRAM_ALIAS     0xa0000000ULL
#define SOC_UART_BASE      0x40000000ULL
#define SOC_UART_SIZE      0x1000
#define SOC_MAILBOX_BASE   0xa000fffcULL
#define SOC_MAILBOX_MAGIC  0xdeadbeefU
#define SOC_DDR_BASE       0x08000000ULL
#define SOC_DDR_SIZE       (128 * MiB)
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
    uint32_t timer_ctrl;
    uint32_t timer_load;
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
    GArray *irq_release_after;
    guint irq_release_index;
    bool irq_replay_enabled;
    bool irq_replay_armed;
    bool irq_replay_wake_pending;
    bool irq_replay_epc_fixup;
    target_ulong irq_replay_epc;
    uint32_t irq_replay_pic_mask;
} MIPS32SocRefState;

typedef struct MIPS32SocRefResetData {
    MIPSCPU *cpu;
    uint64_t vector;
    target_ulong fdt_addr;
    bool fdt_loaded;
    bool software_mmu_guest;
    bool cpu_has_fpu;
} MIPS32SocRefResetData;

static char *soc_ref_qspi_image;
static char *soc_ref_irq_schedule;
static uint32_t soc_ref_irq_replay_pic_mask;
static char *soc_ref_dma_event_trace_path;
static uint32_t soc_ref_dma_fault_mode;
static bool soc_ref_dma_reset_inflight;
static uint32_t soc_ref_gpio_input;
static bool soc_ref_malta_uboot_compat;
static uint32_t soc_ref_ddr_fault_mode;
static bool soc_ref_software_mmu_guest;
static bool soc_ref_software_mmu_bootrom_guest;
static MIPS32SocRefState *soc_ref_active_state;

/*
 * The patched QEMU TLB helper uses this callback to select the project's
 * fixed general-exception vector for software-managed MMU guests.  Keep it
 * machine-scoped so ordinary mips targets and the default identity-TLB path
 * retain upstream exception-vector behavior.
 */
bool qemu_mips32_soc_ref_rtl_mmu_guest(void)
{
    return soc_ref_software_mmu_guest;
}

bool qemu_mips32_soc_ref_bootrom_mmu_guest(void)
{
    return soc_ref_software_mmu_bootrom_guest;
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
bool qemu_mips32_soc_ref_irq_replay_active(void);
void helper_soc_ref_retire_tick(CPUMIPSState *env);

bool qemu_mips32_soc_ref_irq_replay_active(void)
{
    return soc_ref_active_state && soc_ref_active_state->irq_replay_enabled;
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

static bool soc_ref_get_malta_uboot_compat(Object *obj, Error **errp)
{
    return soc_ref_malta_uboot_compat;
}

static void soc_ref_set_malta_uboot_compat(Object *obj, bool value,
                                           Error **errp)
{
    soc_ref_malta_uboot_compat = value;
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

static void soc_ref_load_irq_schedule(MIPS32SocRefState *s)
{
    g_autofree gchar *contents = NULL;
    g_auto(GStrv) lines = NULL;
    gsize length = 0;

    if (!soc_ref_irq_schedule || !*soc_ref_irq_schedule) {
        return;
    }
    if (!g_file_get_contents(soc_ref_irq_schedule, &contents, &length, NULL)) {
        error_report("could not load IRQ schedule '%s'", soc_ref_irq_schedule);
        exit(EXIT_FAILURE);
    }
    s->irq_release_after = g_array_new(false, false, sizeof(uint64_t));
    lines = g_strsplit(contents, "\n", -1);
    for (guint i = 0; lines[i]; ++i) {
        gchar *end = NULL;
        guint64 value;
        if (!*lines[i] || lines[i][0] == '#') {
            continue;
        }
        value = g_ascii_strtoull(lines[i], &end, 10);
        if (!end || *end || value == 0 ||
            (s->irq_release_after->len &&
             value <= g_array_index(s->irq_release_after, uint64_t,
                                    s->irq_release_after->len - 1))) {
            error_report("invalid IRQ schedule entry '%s'", lines[i]);
            exit(EXIT_FAILURE);
        }
        g_array_append_val(s->irq_release_after, value);
    }
    if (!s->irq_release_after->len) {
        error_report("IRQ schedule '%s' has no release entries",
                     soc_ref_irq_schedule);
        exit(EXIT_FAILURE);
    }
    s->irq_replay_enabled = true;
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

static uint64_t soc_ref_uart_read(void *opaque, hwaddr addr, unsigned size)
{
    MIPS32SocRefState *s = opaque;
    unsigned reg = addr >> 2;

    if (reg == 2) {
        /* IIR: report a pending THRE interrupt while the transmitter is
         * empty and the corresponding IER bit is enabled. */
        return (s->uart_regs[1] & 0x2) ? 0x2 : 0x1;
    }
    if (reg == 5) {
        /* 16550 LSR: transmitter holding register and transmitter empty. */
        return 0x60;
    }
    if (reg < ARRAY_SIZE(s->uart_regs)) {
        return s->uart_regs[reg];
    }
    return 0;
}

static void soc_ref_uart_update_irq(MIPS32SocRefState *s)
{
    if (!s->cpu)
        return;
    /* Linux uses the CPU interrupt-controller line directly for this UART.
     * IER.THRI plus an empty holding register produces a level interrupt. */
    qemu_set_irq(s->cpu->env.irq[4], (s->uart_regs[1] & 0x2) != 0);
}

static void soc_ref_uart_write(void *opaque, hwaddr addr, uint64_t data,
                               unsigned size)
{
    MIPS32SocRefState *s = opaque;
    unsigned reg = addr >> 2;

    if (reg == 0) {
        uint8_t ch = data & 0xff;
        putchar(ch);
        fflush(stdout);
        soc_ref_uart_update_irq(s);
        return;
    }
    if (reg < ARRAY_SIZE(s->uart_regs)) {
        s->uart_regs[reg] = data;
        if (reg == 1)
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

static void soc_ref_instruction_tick(CPUState *cpu)
{
    MIPS32SocRefState *s = soc_ref_active_state;
    uint64_t release_after;

    if (!s || CPU(s->cpu) != cpu || !s->irq_replay_enabled) {
        return;
    }
    ++s->retire_count;
    if (s->irq_replay_wake_pending) {
        s->irq_replay_wake_pending = false;
        /* The RTL records the WAIT wakeup exception against the sequential
         * instruction at the wake boundary, before that instruction retires. */
        s->irq_replay_epc = s->cpu->env.active_tc.PC;
        s->irq_replay_epc_fixup = true;
        bql_lock();
        cpu_interrupt(cpu, CPU_INTERRUPT_HARD);
        bql_unlock();
        cpu_exit(cpu);
        return;
    }
    if (s->irq_release_index >= s->irq_release_after->len) {
        return;
    }
    release_after = g_array_index(s->irq_release_after, uint64_t,
                                  s->irq_release_index);
    if (s->retire_count != release_after) {
        return;
    }
    s->irq_replay_armed = true;
    if (s->irq_release_index == 0 && s->irq_replay_pic_mask) {
        /* Some RTL IRQ replays originate in the SoC VIC.  The CPU replay
         * line is injected independently, so mirror the explicitly supplied
         * VIC software sources before delivering the first exception. */
        s->pic_soft |= s->irq_replay_pic_mask;
        s->pic_mask |= s->irq_replay_pic_mask;
    }
    ++s->irq_release_index;
    soc_ref_update_irq(s);
    cpu_exit(cpu);
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

    if (!s || !s->irq_replay_enabled ||
        s->irq_release_index >= s->irq_release_after->len) {
        return;
    }
    release_after = g_array_index(s->irq_release_after, uint64_t,
                                  s->irq_release_index);
    if (s->retire_count + 1 != release_after) {
        return;
    }
    ++s->retire_count;
    ++s->irq_release_index;
    qemu_set_irq(env->irq[0], true);
    bql_lock();
    s->irq_replay_wake_pending = true;
    cpu_interrupt(env_cpu(env), CPU_INTERRUPT_WAKE);
    bql_unlock();
}

void helper_soc_ref_retire_tick(CPUMIPSState *env)
{
    soc_ref_instruction_tick(env_cpu(env));
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
        return s->timer_load;
    }
    now = qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL);
    if (now >= s->timer_deadline) {
        return 0;
    }
    remaining = s->timer_deadline - now;
    return (remaining + 19) / 20; /* 50 MHz reference clock */
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
    case 0x1000:
        s->timer_ctrl = value;
        if (!(value & 1)) {
            s->timer_deadline = 0;
            timer_del(s->timer);
        } else if (s->timer_load) {
            s->timer_deadline = qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL) +
                                 (uint64_t)s->timer_load * 20;
            timer_mod(s->timer, s->timer_deadline);
        }
        soc_ref_update_irq(s);
        break;
    case 0x1004: s->timer_load = value; s->timer_deadline = qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL) + (uint64_t)value * 20; if (s->timer_ctrl & 1) timer_mod(s->timer, s->timer_deadline); break;
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
    /* Match the opt-in RTL SRSCtl static HSS field.  CSS/PSS/ESS remain
     * software and exception controlled below this implementation. */
    env->CP0_SRSCtl = (0xfU << 23);
    env->active_tc.PC = reset->vector & ~(target_ulong)1;
    if (reset->vector & 1) {
        env->hflags |= MIPS_HFLAG_M16;
    }

    /* The 24Kf model exposes an FPU, but its system-mode Status write mask
     * does not retain CU1 for this bare-metal machine.  Keep CU1 clear at
     * reset so the negative COP1 gate remains meaningful, while allowing the
     * guest's normal MTC0 Status sequence to enable COP1. */
    env->CP0_Status_rw_bitmask |= (1U << CP0St_CU1);

    /* Bare-metal differential guests use the RTL's fixed CP0 identity and
     * geometry. UHI/Linux guests must retain the selected QEMU CPU's native
     * identification: Linux cpu_probe uses PRid/Config to select errata and
     * traps if the prototype values describe an unknown processor. */
    if (!reset->fdt_loaded) {
        env->CP0_PRid = 0x00008010;
        env->CP0_Config0 = 0x80000503;
        env->CP0_Config1 = 0xFEA83480;
        if (reset->cpu_has_fpu) {
            /* COP1 availability is controlled by Status.CU1 after reset. */
            env->CP0_Config1 |= (1U << CP0C1_FP);
        }
        env->CP0_Config2 = 0x80000000;
        env->CP0_Config3 = 0x00002008;
    }

    if (reset->fdt_loaded) {
        /* Linux generic MIPS consumes the UHI FDT contract before C code:
         * a0=-2 identifies UHI and a1 is the kseg0 virtual FDT address. */
        env->active_tc.gpr[4] = (target_ulong)-2;
        env->active_tc.gpr[5] = reset->fdt_addr;
        env->active_tc.gpr[6] = 0;
        env->active_tc.gpr[7] = 0;
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

    cpuclk = clock_new(OBJECT(machine), "cpu-refclk");
    clock_set_hz(cpuclk, 50 * 1000 * 1000);
    cpu = mips_cpu_create_with_clock(machine->cpu_type, cpuclk, false);
    state->cpu = cpu;
    state->irq_replay_pic_mask = soc_ref_irq_replay_pic_mask;
    state->sram = machine->ram;
    state->gpio_input = soc_ref_gpio_input;
    state->dma_fault_mode = soc_ref_dma_fault_mode;
    state->ddr_fault_mode = soc_ref_ddr_fault_mode;
    soc_ref_load_irq_schedule(state);
    soc_ref_active_state = state;
    if (soc_ref_dma_event_trace_path) {
        state->dma_event_trace = fopen(soc_ref_dma_event_trace_path, "w");
        if (!state->dma_event_trace) {
            error_report("could not open DMA event trace '%s'", soc_ref_dma_event_trace_path);
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
        /* Keep the blob below the 256 MiB MIPS32 physical limit and outside
         * the first SRAM page used by reset images. Linux receives kseg0. */
        if (machine->ram_size < (2 * MiB)) {
            error_report("-dtb requires at least 2 MiB of guest RAM");
            exit(EXIT_FAILURE);
        }
        fdt_base = (machine->ram_size - SOC_FDT_MAX_SIZE) & ~0xfffULL;
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
    object_class_property_add_bool(OBJECT_CLASS(mc), "malta-u-boot-compat",
                                   soc_ref_get_malta_uboot_compat,
                                   soc_ref_set_malta_uboot_compat);
    object_class_property_add_str(OBJECT_CLASS(mc), "irq-schedule",
                                  soc_ref_get_irq_schedule,
                                  soc_ref_set_irq_schedule);
    object_class_property_add_uint32_ptr(OBJECT_CLASS(mc),
                                         "irq-replay-pic-mask",
                                         &soc_ref_irq_replay_pic_mask,
                                         OBJ_PROP_FLAG_WRITE);
    object_class_property_add_str(OBJECT_CLASS(mc), "dma-event-trace",
                                  soc_ref_get_dma_event_trace,
                                  soc_ref_set_dma_event_trace);
    object_class_property_add_uint32_ptr(OBJECT_CLASS(mc), "dma-fault-mode",
                                         &soc_ref_dma_fault_mode,
                                         OBJ_PROP_FLAG_WRITE);
    object_class_property_add_bool(OBJECT_CLASS(mc), "dma-reset-inflight",
                                   soc_ref_get_dma_reset_inflight,
                                   soc_ref_set_dma_reset_inflight);
    object_class_property_add_uint32_ptr(OBJECT_CLASS(mc), "gpio-input",
                                         &soc_ref_gpio_input,
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
