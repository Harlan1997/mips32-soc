/*
 * QEMU focus plugin for Linux RTL bring-up diagnostics.
 *
 * Records architectural state transitions for target GPRs (a0, a1, t5, t9,
 * v0, v1, sp, ra, r30) at discrete checkpoint PCs and configurable PC windows.
 * Register values are sampled at instruction boundaries; values in retired
 * records represent the committed architectural state after the instruction
 * has completed execution.
 */
#include <ctype.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <glib.h>
#include <qemu-plugin.h>

QEMU_PLUGIN_EXPORT int qemu_plugin_version = QEMU_PLUGIN_VERSION;

typedef struct {
    uint32_t v0;  /* r2  */
    uint32_t v1;  /* r3  */
    uint32_t a0;  /* r4  */
    uint32_t a1;  /* r5  */
    uint32_t t5;  /* r13 */
    uint32_t t9;  /* r25 */
    uint32_t sp;  /* r29 */
    uint32_t r30; /* r30 */
    uint32_t ra;  /* r31 */
} FocusGPRs;

typedef struct {
    uint32_t status;
    uint32_t cause;
    uint32_t epc;
    uint32_t badvaddr;
} FocusCP0;

typedef struct {
    bool valid;
    bool read;
    bool write;
    uint64_t addr;
    uint32_t value;
    unsigned int size;
} FocusMem;

typedef struct {
    uint64_t pc;
    uint32_t instr;
    FocusGPRs before_gprs;
    FocusCP0 before_cp0;
    FocusMem mem;
    bool valid;
} PreviousInsn;

static FILE *out;
static struct qemu_plugin_register *reg_handles[32];
static struct qemu_plugin_register *status_handle;
static struct qemu_plugin_register *cause_handle;
static struct qemu_plugin_register *epc_handle;
static struct qemu_plugin_register *badvaddr_handle;
static PreviousInsn previous;
static uint32_t focus_value = 0x89508405U;
static uint32_t focus_start = 0x88a35000U;
static uint32_t focus_end = 0x88a40000U;
static uint64_t records;
static uint64_t max_records = 16384;
static bool entry_only;
static bool target_only;
static bool default_targets_enabled = true;

/* Default discrete target PCs from architectural blocker review */
static const uint32_t default_target_pcs[] = {
    0x88a38c1cU, 0x88a38c24U,
    0x88a38978U, 0x88a3897cU, 0x88a38980U, 0x88a38984U,
    0x88a3898cU, 0x88a38998U
};

#define MAX_CUSTOM_PCS 64
static uint32_t custom_pcs[MAX_CUSTOM_PCS];
static size_t custom_pc_count;

static uint32_t parse_hex(const char *text, const char *name)
{
    char *end = NULL;
    unsigned long value;

    value = strtoul(text, &end, 16);
    if (!text[0] || !end || *end != '\0' || value > UINT32_MAX) {
        fprintf(stderr, "qemu gpr focus: invalid %s=%s\n", name, text);
        exit(EXIT_FAILURE);
    }
    return (uint32_t)value;
}

static uint64_t parse_decimal(const char *text, const char *name)
{
    char *end = NULL;
    unsigned long long value;

    value = strtoull(text, &end, 10);
    if (!text[0] || !end || *end != '\0' || value == 0) {
        fprintf(stderr, "qemu gpr focus: invalid %s=%s\n", name, text);
        exit(EXIT_FAILURE);
    }
    return (uint64_t)value;
}

static void parse_pc_list(const char *text)
{
    /* QEMU plugin options use comma as their own delimiter.  Accept ';' as
     * an unambiguous list separator so callers can pass multiple PCs without
     * relying on version-specific backslash handling. */
    g_auto(GStrv) tokens = g_strsplit_set(text, ",;", -1);
    for (int i = 0; tokens && tokens[i]; ++i) {
        if (tokens[i][0] == '\0') {
            continue;
        }
        if (custom_pc_count >= MAX_CUSTOM_PCS) {
            fprintf(stderr, "qemu gpr focus: too many custom target PCs (max %d)\n",
                    MAX_CUSTOM_PCS);
            exit(EXIT_FAILURE);
        }
        custom_pcs[custom_pc_count++] = parse_hex(tokens[i], "pc-list entry");
    }
}

static bool is_target_pc(uint64_t pc)
{
    size_t i;
    if (default_targets_enabled) {
        for (i = 0; i < sizeof(default_target_pcs) / sizeof(default_target_pcs[0]); ++i) {
            if (pc == default_target_pcs[i]) {
                return true;
            }
        }
    }
    for (i = 0; i < custom_pc_count; ++i) {
        if (pc == custom_pcs[i]) {
            return true;
        }
    }
    return false;
}

static bool pc_in_focus(uint64_t pc)
{
    if (is_target_pc(pc)) {
        return true;
    }
    if (target_only) {
        return false;
    }
    return pc >= focus_start && pc <= focus_end;
}

/* Conservative decoder for r30 write detection */
static bool may_write_r30(uint32_t insn)
{
    uint32_t op = insn >> 26;
    uint32_t rt = (insn >> 16) & 31U;
    uint32_t rd = (insn >> 11) & 31U;
    uint32_t funct = insn & 63U;

    if (op == 0) {
        if (rd != 30U) {
            return false;
        }
        return funct != 8U && funct != 9U && funct != 12U && funct != 13U &&
               funct != 15U && funct != 16U && funct != 17U && funct != 18U &&
               funct != 19U && funct != 24U && funct != 25U && funct != 26U &&
               funct != 27U && funct != 28U && funct != 29U && funct != 30U &&
               funct != 32U && funct != 33U && funct != 34U && funct != 35U &&
               funct != 36U && funct != 37U && funct != 38U && funct != 39U &&
               funct != 42U && funct != 43U;
    }
    if (op == 0x1cU) {
        return rd == 30U;
    }
    if (op == 0x10U || op == 0x11U) {
        return rt == 30U;
    }
    if (op == 0x02U || op == 0x03U || op == 0x04U || op == 0x05U ||
        op == 0x06U || op == 0x07U || op == 0x14U || op == 0x15U ||
        op == 0x16U || op == 0x17U) {
        return false;
    }
    return rt == 30U;
}

static bool read_reg(int reg_num, uint32_t *value)
{
    if (reg_num == 0) {
        *value = 0;
        return true;
    }
    if (reg_num < 0 || reg_num >= 32 || !reg_handles[reg_num]) {
        return false;
    }
    g_autoptr(GByteArray) bytes = g_byte_array_new();
    int size = qemu_plugin_read_register(reg_handles[reg_num], bytes);
    if (size <= 0 || bytes->len < 4) {
        return false;
    }
    /* QEMU mipsel register bytes are in target little-endian order:
     * data[0] is LSB, data[3] is MSB. */
    *value = ((uint32_t)bytes->data[3] << 24) |
             ((uint32_t)bytes->data[2] << 16) |
             ((uint32_t)bytes->data[1] << 8) |
             (uint32_t)bytes->data[0];
    return true;
}

static bool read_named_reg(struct qemu_plugin_register *handle, uint32_t *value)
{
    g_autoptr(GByteArray) bytes = g_byte_array_new();
    int size;

    if (!handle) {
        return false;
    }
    size = qemu_plugin_read_register(handle, bytes);
    if (size <= 0 || bytes->len < 4) {
        return false;
    }
    *value = ((uint32_t)bytes->data[3] << 24) |
             ((uint32_t)bytes->data[2] << 16) |
             ((uint32_t)bytes->data[1] << 8) |
             (uint32_t)bytes->data[0];
    return true;
}

static bool read_focus_gprs(FocusGPRs *gprs)
{
    bool ok = true;
    ok &= read_reg(2, &gprs->v0);
    ok &= read_reg(3, &gprs->v1);
    ok &= read_reg(4, &gprs->a0);
    ok &= read_reg(5, &gprs->a1);
    ok &= read_reg(13, &gprs->t5);
    ok &= read_reg(25, &gprs->t9);
    ok &= read_reg(29, &gprs->sp);
    ok &= read_reg(30, &gprs->r30);
    ok &= read_reg(31, &gprs->ra);
    return ok;
}

static bool read_focus_cp0(FocusCP0 *cp0)
{
    return read_named_reg(status_handle, &cp0->status) &&
           read_named_reg(cause_handle, &cp0->cause) &&
           read_named_reg(epc_handle, &cp0->epc) &&
           read_named_reg(badvaddr_handle, &cp0->badvaddr);
}

static void emit_previous(const FocusGPRs *current_gprs,
                          const FocusCP0 *current_cp0,
                          uint64_t next_pc)
{
    bool interesting;

    if (!previous.valid || !out || records >= max_records) {
        return;
    }
    interesting = ((!entry_only && pc_in_focus(previous.pc)) ||
                   (entry_only && previous.pc == focus_start)) ||
                  (may_write_r30(previous.instr) &&
                   (previous.before_gprs.r30 == focus_value ||
                    current_gprs->r30 == focus_value));
    if (!interesting) {
        return;
    }

    /* Structured focus record: phase=retired means GPRs represent the committed
     * state after previous.instr has completed execution. */
    fprintf(out,
            "QEMU_FOCUS seq=%" PRIu64 " phase=retired pc=%08" PRIx64 " instr=%08" PRIx32
            " a0=%08" PRIx32 " a1=%08" PRIx32 " t5=%08" PRIx32 " t9=%08" PRIx32
            " v0=%08" PRIx32 " v1=%08" PRIx32 " sp=%08" PRIx32 " ra=%08" PRIx32
            " r30=%08" PRIx32 " mem=%u/%u/%u/%08" PRIx64 "/%08" PRIx32 "/%u\n",
            records, previous.pc, previous.instr,
            current_gprs->a0, current_gprs->a1, current_gprs->t5, current_gprs->t9,
            current_gprs->v0, current_gprs->v1, current_gprs->sp, current_gprs->ra,
            current_gprs->r30, previous.mem.valid, previous.mem.read,
            previous.mem.write, previous.mem.addr, previous.mem.value,
            previous.mem.size);

    fprintf(out,
            "QEMU_FOCUS_EVENT seq=%" PRIu64 " pc=%08" PRIx64
            " next_pc=%08" PRIx64 " status=%08" PRIx32
            " cause=%08" PRIx32 " epc=%08" PRIx32 " badv=%08" PRIx32 "\n",
            records, previous.pc, next_pc, current_cp0->status,
            current_cp0->cause, current_cp0->epc, current_cp0->badvaddr);

    /* Backward-compatible legacy line */
    fprintf(out,
            "QEMU_GPR_FOCUS pc=%08" PRIx64 " instr=%08" PRIx32
            " r30_before=%08" PRIx32 " r30_after=%08" PRIx32 "\n",
            previous.pc, previous.instr, previous.before_gprs.r30, current_gprs->r30);

    fflush(out);
    ++records;
}

static void vcpu_init(qemu_plugin_id_t id, unsigned int cpu_index)
{
    g_autoptr(GArray) list = qemu_plugin_get_registers();
    (void)id;
    if (cpu_index != 0) {
        return;
    }
    for (guint i = 0; i < list->len; ++i) {
        qemu_plugin_reg_descriptor *desc = &g_array_index(
            list, qemu_plugin_reg_descriptor, i);
        if (desc->name && desc->name[0] == 'r') {
            const char *p = &desc->name[1];
            bool all_digits = (*p != '\0');
            while (*p) {
                if (!g_ascii_isdigit(*p)) {
                    all_digits = false;
                    break;
                }
                p++;
            }
            if (all_digits) {
                int reg_num = atoi(&desc->name[1]);
                if (reg_num >= 0 && reg_num < 32) {
                    reg_handles[reg_num] = desc->handle;
                }
            }
        } else if (g_strcmp0(desc->name, "status") == 0) {
            status_handle = desc->handle;
        } else if (g_strcmp0(desc->name, "cause") == 0) {
            cause_handle = desc->handle;
        } else if (g_strcmp0(desc->name, "epc") == 0) {
            epc_handle = desc->handle;
        } else if (g_strcmp0(desc->name, "badvaddr") == 0) {
            badvaddr_handle = desc->handle;
        }
    }
    /* Verify mandatory register handles are present */
    const int mandatory_regs[] = {2, 3, 4, 5, 13, 25, 29, 30, 31};
    for (size_t i = 0; i < sizeof(mandatory_regs) / sizeof(mandatory_regs[0]); ++i) {
        int r = mandatory_regs[i];
        if (!reg_handles[r]) {
            fprintf(stderr, "qemu gpr focus: QEMU did not expose r%d\n", r);
            exit(EXIT_FAILURE);
        }
    }
    if (!status_handle || !cause_handle || !epc_handle || !badvaddr_handle) {
        fprintf(stderr, "qemu gpr focus: QEMU did not expose CP0 state registers\n");
        exit(EXIT_FAILURE);
    }
}

static void vcpu_insn_exec(unsigned int cpu_index, void *userdata)
{
    FocusGPRs current_gprs;
    FocusCP0 current_cp0;
    uint32_t *encoded = userdata;
    uint64_t current_pc = encoded[0];
    bool need_current_regs;
    bool have_current_regs = false;
    (void)cpu_index;

    /* Register reads are expensive in QEMU's plugin API.  The old callback
     * read the complete architectural state for every instruction, which
     * made a focused post-boot PC unreachable before the host timeout.  Keep
     * the one-instruction look-ahead semantics, but sample only when either
     * side of the pair can produce a record. */
    need_current_regs = pc_in_focus(current_pc) ||
                        may_write_r30(encoded[1]) ||
                        (previous.valid &&
                         (pc_in_focus(previous.pc) ||
                          may_write_r30(previous.instr)));
    if (need_current_regs) {
        if (!read_focus_gprs(&current_gprs) ||
            !read_focus_cp0(&current_cp0)) {
            return;
        }
        have_current_regs = true;
        if (previous.valid &&
            (pc_in_focus(previous.pc) ||
             (may_write_r30(previous.instr) &&
              (previous.before_gprs.r30 == focus_value ||
               current_gprs.r30 == focus_value)))) {
            emit_previous(&current_gprs, &current_cp0, current_pc);
        }
    }

    previous.pc = current_pc;
    previous.instr = encoded[1];
    if (have_current_regs) {
        previous.before_gprs = current_gprs;
        previous.before_cp0 = current_cp0;
    }
    previous.mem = (FocusMem){0};
    previous.valid = true;
}

static void vcpu_mem(unsigned int cpu_index, qemu_plugin_meminfo_t info,
                     uint64_t vaddr, void *userdata)
{
    qemu_plugin_mem_value value;
    (void)userdata;
    if (cpu_index != 0 || !previous.valid) {
        return;
    }
    value = qemu_plugin_mem_get_value(info);
    previous.mem.valid = true;
    previous.mem.read = !qemu_plugin_mem_is_store(info);
    previous.mem.write = qemu_plugin_mem_is_store(info);
    previous.mem.addr = vaddr;
    previous.mem.size = 1u << qemu_plugin_mem_size_shift(info);
    switch (value.type) {
    case QEMU_PLUGIN_MEM_VALUE_U8: previous.mem.value = value.data.u8; break;
    case QEMU_PLUGIN_MEM_VALUE_U16: previous.mem.value = value.data.u16; break;
    case QEMU_PLUGIN_MEM_VALUE_U32: previous.mem.value = value.data.u32; break;
    default: previous.mem.value = 0; break;
    }
}

static void vcpu_tb_trans(qemu_plugin_id_t id, struct qemu_plugin_tb *tb)
{
    (void)id;
    for (size_t i = 0; i < qemu_plugin_tb_n_insns(tb); ++i) {
        struct qemu_plugin_insn *insn = qemu_plugin_tb_get_insn(tb, i);
        uint32_t *encoded = g_new0(uint32_t, 2);
        encoded[0] = (uint32_t)qemu_plugin_insn_vaddr(insn);
        qemu_plugin_insn_data(insn, &encoded[1], sizeof(encoded[1]));
        qemu_plugin_register_vcpu_mem_cb(insn, vcpu_mem, QEMU_PLUGIN_CB_NO_REGS,
                                         QEMU_PLUGIN_MEM_RW, NULL);
        qemu_plugin_register_vcpu_insn_exec_cb(
            insn, vcpu_insn_exec, QEMU_PLUGIN_CB_R_REGS, encoded);
    }
}

static void plugin_exit(qemu_plugin_id_t id, void *userdata)
{
    (void)id;
    (void)userdata;
    /*
     * The atexit callback has no current vCPU.  Register reads here are
     * rejected by QEMU's plugin API and can abort the whole reference run.
     * The instruction callback emits each completed record when the next
     * legal vCPU callback samples its state.  A final instruction without a
     * following callback is intentionally incomplete and must be rejected by
     * the trace checker rather than guessed at shutdown.
     */
    if (out) {
        fprintf(out, "QEMU_FOCUS_SUMMARY records=%" PRIu64 " final_record=deferred\n", records);
        fflush(out);
        fclose(out);
        out = NULL;
    }
}

QEMU_PLUGIN_EXPORT int qemu_plugin_install(qemu_plugin_id_t id,
                                           const qemu_info_t *info,
                                           int argc, char **argv)
{
    (void)info;
    for (int i = 0; i < argc; ++i) {
        g_auto(GStrv) tokens = g_strsplit(argv[i], "=", 2);
        if (g_strcmp0(tokens[0], "out") == 0 && tokens[1]) {
            out = fopen(tokens[1], "w");
        } else if (g_strcmp0(tokens[0], "value") == 0 && tokens[1]) {
            focus_value = parse_hex(tokens[1], "value");
        } else if (g_strcmp0(tokens[0], "start") == 0 && tokens[1]) {
            focus_start = parse_hex(tokens[1], "start");
        } else if (g_strcmp0(tokens[0], "end") == 0 && tokens[1]) {
            focus_end = parse_hex(tokens[1], "end");
        } else if (g_strcmp0(tokens[0], "max-records") == 0 && tokens[1]) {
            max_records = parse_decimal(tokens[1], "max-records");
        } else if (g_strcmp0(tokens[0], "entry-only") == 0 && tokens[1]) {
            entry_only = g_strcmp0(tokens[1], "on") == 0 ||
                         g_strcmp0(tokens[1], "1") == 0;
        } else if (g_strcmp0(tokens[0], "target-only") == 0 && tokens[1]) {
            target_only = g_strcmp0(tokens[1], "on") == 0 ||
                          g_strcmp0(tokens[1], "1") == 0;
        } else if (g_strcmp0(tokens[0], "default-targets") == 0 && tokens[1]) {
            default_targets_enabled = !(g_strcmp0(tokens[1], "off") == 0 ||
                                        g_strcmp0(tokens[1], "0") == 0);
        } else if (g_strcmp0(tokens[0], "pc-list") == 0 && tokens[1]) {
            parse_pc_list(tokens[1]);
        } else {
            fprintf(stderr, "qemu gpr focus: unknown argument %s\n", argv[i]);
            return -1;
        }
    }
    if (!out) {
        fprintf(stderr, "qemu gpr focus: out=/path is required\n");
        return -1;
    }
    qemu_plugin_register_vcpu_init_cb(id, vcpu_init);
    qemu_plugin_register_vcpu_tb_trans_cb(id, vcpu_tb_trans);
    qemu_plugin_register_atexit_cb(id, plugin_exit, NULL);
    return 0;
}
