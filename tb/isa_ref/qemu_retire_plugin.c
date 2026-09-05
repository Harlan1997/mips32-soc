/* QEMU 9.x plugin: emit one instruction/memory record per guest execution. */
#include <errno.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#include <glib.h>
#include <qemu-plugin.h>

QEMU_PLUGIN_EXPORT int qemu_plugin_version = QEMU_PLUGIN_VERSION;

typedef struct {
    uint64_t pc;
    uint32_t instr;
    bool valid;
    bool mem_valid;
    bool mem_read;
    bool mem_write;
    uint64_t mem_addr;
    uint32_t mem_value;
    unsigned int mem_size;
} Pending;

typedef struct {
    uint64_t pc;
    uint32_t instr;
} InsnInfo;

typedef struct {
    struct qemu_plugin_register *handle;
    const char *name;
} StateRegister;

static Pending *states;
static unsigned int state_count;
static FILE *trace_file;
static char *trace_path;
static FILE *register_file;
static char *register_path;
static FILE *state_file;
static char *state_path;
static char *last_state_line;
static GPtrArray *state_registers;
/* A capture must stop at the source.  Post-run guards cannot prevent a
 * long-running guest from filling the filesystem before QEMU exits. */
static uint64_t max_records = UINT64_MAX;
static uint64_t max_bytes = UINT64_MAX;
static uint64_t record_count;
static uint64_t trace_bytes;
static uint64_t state_bytes;
static bool capture_stopped;
static bool capture_limit_reported;

static bool capture_limit_reached(void)
{
    if (record_count < max_records) {
        return false;
    }
    capture_stopped = true;
    if (!capture_limit_reported) {
        qemu_plugin_outs("qemu retire plugin: capture limit reached; stopping record emission\n");
        capture_limit_reported = true;
    }
    return true;
}

static void vcpu_init(qemu_plugin_id_t id, unsigned int cpu_index)
{
    (void)id;
    g_autoptr(GArray) list = qemu_plugin_get_registers();
    if ((!register_file && !state_file) || cpu_index != 0) {
        return;
    }
    for (guint i = 0; i < list->len; ++i) {
        qemu_plugin_reg_descriptor *desc = &g_array_index(
            list, qemu_plugin_reg_descriptor, i);
        if (register_file) {
            fprintf(register_file, "%s\n", desc->name);
        }
        if (state_file) {
            StateRegister *reg = g_new0(StateRegister, 1);
            reg->handle = desc->handle;
            reg->name = desc->name;
            g_ptr_array_add(state_registers, reg);
        }
    }
    fflush(register_file);
}

static void emit_state(unsigned int cpu_index, InsnInfo *insn)
{
    GString *line;
    (void)cpu_index;
    if (!state_file || !state_registers) {
        return;
    }
    line = g_string_new(NULL);
    g_string_append_printf(line, "{\"pc\":\"%08" PRIx64 "\",\"regs\":{",
                           insn->pc);
    for (guint i = 0; i < state_registers->len; ++i) {
        StateRegister *reg = g_ptr_array_index(state_registers, i);
        g_autoptr(GByteArray) value = g_byte_array_new();
        int size = qemu_plugin_read_register(reg->handle, value);
        g_string_append_printf(line, "%s\"%s\":\"", i ? "," : "", reg->name);
        if (size > 0) {
            for (int b = size - 1; b >= 0; --b) {
                g_string_append_printf(line, "%02x", value->data[b]);
            }
        }
        g_string_append_c(line, '"');
    }
    g_string_append(line, "}}\n");
    if (state_bytes > max_bytes || (uint64_t)line->len > max_bytes - state_bytes) {
        capture_stopped = true;
        if (!capture_limit_reported) {
            qemu_plugin_outs("qemu retire plugin: byte limit reached; stopping record emission\n");
            capture_limit_reported = true;
        }
        g_string_free(line, true);
        return;
    }
    fputs(line->str, state_file);
    state_bytes += (uint64_t)line->len;
    g_free(last_state_line);
    last_state_line = g_strdup(line->str);
    g_string_free(line, true);
    fflush(state_file);
}

static void emit_pending(Pending *pending, uint64_t next_pc)
{
    char line[512];
    int line_len;
    if (!pending->valid) {
        return;
    }
    line_len = snprintf(line, sizeof(line),
            "{\"pc\":\"%08" PRIx64 "\",\"instr\":\"%08" PRIx32
            "\",\"next_pc\":\"%08" PRIx64 "\",\"mem_valid\":%u"
            ",\"mem_read\":%u,\"mem_write\":%u,\"mem_addr\":\"%08" PRIx64
            "\",\"mem_value\":\"%08" PRIx32 "\",\"mem_size\":%u}\n",
            pending->pc, pending->instr, next_pc,
            pending->mem_valid, pending->mem_read, pending->mem_write,
            pending->mem_addr, pending->mem_value, pending->mem_size);
    if (line_len < 0 || (size_t)line_len >= sizeof(line) ||
        trace_bytes > max_bytes || (uint64_t)line_len > max_bytes - trace_bytes) {
        capture_stopped = true;
        if (!capture_limit_reported) {
            qemu_plugin_outs("qemu retire plugin: byte limit reached; stopping record emission\n");
            capture_limit_reported = true;
        }
        pending->valid = false;
        return;
    }
    fputs(line, trace_file);
    trace_bytes += (uint64_t)line_len;
    fflush(trace_file);
    pending->valid = false;
}

static void vcpu_mem(unsigned int cpu_index, qemu_plugin_meminfo_t info,
                     uint64_t vaddr, void *userdata)
{
    (void)userdata;
    if (capture_stopped) {
        return;
    }
    Pending *pending = &states[cpu_index];
    qemu_plugin_mem_value value = qemu_plugin_mem_get_value(info);

    pending->mem_valid = true;
    pending->mem_read = !qemu_plugin_mem_is_store(info);
    pending->mem_write = qemu_plugin_mem_is_store(info);
    pending->mem_addr = vaddr;
    pending->mem_size = 1u << qemu_plugin_mem_size_shift(info);
    switch (value.type) {
    case QEMU_PLUGIN_MEM_VALUE_U8: pending->mem_value = value.data.u8; break;
    case QEMU_PLUGIN_MEM_VALUE_U16: pending->mem_value = value.data.u16; break;
    case QEMU_PLUGIN_MEM_VALUE_U32: pending->mem_value = value.data.u32; break;
    default: pending->mem_value = 0; break;
    }
}

static void vcpu_insn_exec(unsigned int cpu_index, void *userdata)
{
    Pending *pending = &states[cpu_index];
    InsnInfo *insn = userdata;

    if (capture_limit_reached()) {
        return;
    }
    emit_state(cpu_index, insn);
    emit_pending(pending, insn->pc);
    ++record_count;
    pending->pc = insn->pc;
    pending->instr = insn->instr;
    pending->valid = true;
    pending->mem_valid = false;
    pending->mem_read = false;
    pending->mem_write = false;
    pending->mem_addr = 0;
    pending->mem_value = 0;
    pending->mem_size = 0;
}

static void vcpu_exit(qemu_plugin_id_t id, unsigned int cpu_index)
{
    (void)id;
    emit_pending(&states[cpu_index], states[cpu_index].pc + 4);
}

static void vcpu_tb_trans(qemu_plugin_id_t id, struct qemu_plugin_tb *tb)
{
    (void)id;
    for (size_t i = 0; i < qemu_plugin_tb_n_insns(tb); ++i) {
        struct qemu_plugin_insn *insn = qemu_plugin_tb_get_insn(tb, i);
        InsnInfo *info = g_new0(InsnInfo, 1);
        info->pc = qemu_plugin_insn_vaddr(insn);
        qemu_plugin_insn_data(insn, &info->instr, sizeof(info->instr));
        qemu_plugin_register_vcpu_mem_cb(insn, vcpu_mem, QEMU_PLUGIN_CB_NO_REGS,
                                         QEMU_PLUGIN_MEM_RW, NULL);
        qemu_plugin_register_vcpu_insn_exec_cb(insn, vcpu_insn_exec,
                                               state_file ? QEMU_PLUGIN_CB_R_REGS :
                                                            QEMU_PLUGIN_CB_NO_REGS,
                                               info);
    }
}

static void plugin_exit(qemu_plugin_id_t id, void *userdata)
{
    (void)id;
    (void)userdata;
    /* A mailbox write can request guest shutdown from its memory callback
     * before QEMU delivers vcpu_exit.  Flush the instruction whose execution
     * callback already ran so the terminal retire event is not lost. */
    if (states) {
        for (unsigned int i = 0; i < state_count; ++i) {
            emit_pending(&states[i], states[i].pc + 4);
            if (last_state_line) {
                /* plugin_exit has no current vCPU, so emit_state cannot read
                 * registers here. The terminal mailbox store has no state
                 * side effect; duplicating the last snapshot supplies the
                 * required post-state without violating plugin API rules. */
                fputs(last_state_line, state_file);
            }
        }
    }
    fflush(trace_file);
    fclose(trace_file);
    if (register_file) {
        fclose(register_file);
    }
    if (state_file) {
        fclose(state_file);
    }
    g_free(trace_path);
    g_free(register_path);
    g_free(state_path);
    g_free(last_state_line);
    if (state_registers) {
        g_ptr_array_free(state_registers, true);
    }
    g_free(states);
}

QEMU_PLUGIN_EXPORT int qemu_plugin_install(qemu_plugin_id_t id,
                                           const qemu_info_t *info,
                                           int argc, char **argv)
{
    for (int i = 0; i < argc; ++i) {
        g_auto(GStrv) tokens = g_strsplit(argv[i], "=", 2);
        if (g_strcmp0(tokens[0], "trace") == 0 && tokens[1]) {
            g_free(trace_path);
            trace_path = g_strdup(tokens[1]);
        } else if (g_strcmp0(tokens[0], "registers") == 0 && tokens[1]) {
            g_free(register_path);
            register_path = g_strdup(tokens[1]);
            register_file = fopen(register_path, "w");
            if (!register_file) {
                fprintf(stderr, "qemu retire plugin: cannot open register output\n");
                return -1;
            }
        } else if (g_strcmp0(tokens[0], "state") == 0 && tokens[1]) {
            g_free(state_path);
            state_path = g_strdup(tokens[1]);
            state_file = fopen(state_path, "w");
            if (!state_file) {
                fprintf(stderr, "qemu retire plugin: cannot open state output\n");
                return -1;
            }
        } else if (g_strcmp0(tokens[0], "max-records") == 0 && tokens[1]) {
            char *end = NULL;
            errno = 0;
            max_records = g_ascii_strtoull(tokens[1], &end, 10);
            if (errno != 0 || end == tokens[1] || *end != '\0' || max_records == 0) {
                fprintf(stderr, "qemu retire plugin: max-records must be a positive integer\n");
                return -1;
            }
        } else if (g_strcmp0(tokens[0], "max-bytes") == 0 && tokens[1]) {
            char *end = NULL;
            errno = 0;
            max_bytes = g_ascii_strtoull(tokens[1], &end, 10);
            if (errno != 0 || end == tokens[1] || *end != '\0' || max_bytes == 0) {
                fprintf(stderr, "qemu retire plugin: max-bytes must be a positive integer\n");
                return -1;
            }
        } else {
            fprintf(stderr, "qemu retire plugin: expected trace=/path, state=/path, max-records=N or max-bytes=N, got %s\n", argv[i]);
            return -1;
        }
    }
    if (!trace_path || !(trace_file = fopen(trace_path, "w"))) {
        fprintf(stderr, "qemu retire plugin: cannot open trace output\n");
        return -1;
    }
    state_count = info->system_emulation ? info->system.max_vcpus : 1;
    states = g_new0(Pending, state_count);
    if (state_file) {
        state_registers = g_ptr_array_new();
    }
    qemu_plugin_register_vcpu_exit_cb(id, vcpu_exit);
    qemu_plugin_register_vcpu_tb_trans_cb(id, vcpu_tb_trans);
    if (register_file || state_file) {
        qemu_plugin_register_vcpu_init_cb(id, vcpu_init);
    }
    qemu_plugin_register_atexit_cb(id, plugin_exit, NULL);
    return 0;
}
