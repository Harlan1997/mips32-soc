/* QEMU 9.x plugin: emit one instruction/memory record per guest execution. */
#include <errno.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

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
    uint32_t mem_value_hi;
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
static FILE *status_file;
static char *status_path;
static FILE *debug_file;
static char *debug_path;
static FILE *mdu_trace_file;
static char *mdu_trace_path;
static char *uart_trace_path;
static char *last_state_line;
static GPtrArray *state_registers;
static bool trace_is_fifo;
static bool state_is_fifo;
/* A capture must stop at the source.  Post-run guards cannot prevent a
 * long-running guest from filling the filesystem before QEMU exits. */
static uint64_t max_records = UINT64_MAX;
static uint64_t max_bytes = UINT64_MAX;
static uint64_t record_count;
static uint64_t trace_bytes;
static uint64_t state_bytes;
static bool capture_stopped;
static bool capture_limit_reported;
static bool terminal_detection_enabled;
static bool summary_only;
static bool terminal_marker_seen;
static bool terminal_record_reported;
static unsigned int terminal_progress;
static uint64_t terminal_record;
static const char terminal_marker[] = "MIPS32_SOC_LINUX_TERMINAL\n";
/* QEMU may invoke plugin callbacks from more than one vCPU thread even when
 * the guest is configured with a single active CPU.  Serialize FIFO writes so
 * a complete JSON record can never be interleaved with another callback. */
static GMutex fifo_write_mutex;
static bool fifo_write_mutex_initialized;
static bool capture_fpr_state;

static bool configure_output_buffering(FILE *file)
{
    struct stat info;
    bool is_fifo = false;

    /* FIFO consumers need complete JSON records.  A regular-file capture can
     * keep the existing large buffer without paying one write per retire. */
    if (fstat(fileno(file), &info) == 0 && S_ISFIFO(info.st_mode)) {
        is_fifo = true;
        setvbuf(file, NULL, _IOLBF, 0);
    } else {
        setvbuf(file, NULL, _IOFBF, 1U << 20);
    }
    return is_fifo;
}

static int write_record(FILE *file, bool is_fifo, const char *data, size_t len)
{
    if (!is_fifo) {
        return fwrite(data, 1, len, file) == len ? 0 : -1;
    }

    /* A complete JSON record must reach the FIFO as one producer write.  The
     * line-buffered stdio path can split a record under sustained backpressure,
     * allowing the live converter to observe a truncated JSON line. */
    int result = 0;
    int fd = fileno(file);
    size_t offset = 0;
    g_mutex_lock(&fifo_write_mutex);
    while (offset < len) {
        ssize_t written;
        do {
            written = write(fd, data + offset, len - offset);
        } while (written < 0 && errno == EINTR);
        if (written <= 0) {
            result = -1;
            break;
        }
        offset += (size_t)written;
    }
    g_mutex_unlock(&fifo_write_mutex);
    return result;
}

static bool is_numbered_register(const char *name, const char *prefix)
{
    size_t prefix_len = strlen(prefix);
    const char *cursor;

    if (!name || strncmp(name, prefix, prefix_len) != 0) {
        return false;
    }
    cursor = name + prefix_len;
    if (!*cursor) {
        return false;
    }
    for (; *cursor; ++cursor) {
        if (*cursor < '0' || *cursor > '9') {
            return false;
        }
    }
    return true;
}

static bool state_register_needed(const char *name)
{
    if (!name || !name[0]) {
        return false;
    }
    if (is_numbered_register(name, "r") ||
        (capture_fpr_state && is_numbered_register(name, "fpr"))) {
        return true;
    }
    return g_strcmp0(name, "index") == 0 ||
           g_strcmp0(name, "pagemask") == 0 ||
           g_strcmp0(name, "entryhi") == 0 ||
           g_strcmp0(name, "status") == 0 ||
           g_strcmp0(name, "cause") == 0 ||
           g_strcmp0(name, "epc") == 0 ||
           g_strcmp0(name, "hi") == 0 ||
           g_strcmp0(name, "lo") == 0 ||
           g_strcmp0(name, "fcsr") == 0;
}

static bool debug_marker_byte(uint8_t byte)
{
    return byte == 'M' || byte == 'I' || byte == 'P' || byte == 'S' ||
           byte == '3' || byte == '2' || byte == '_' || byte == 'O' ||
           byte == 'C' || byte == 'L' || byte == 'N' || byte == 'T' ||
           byte == 'E' || byte == 'R' || byte == 'A' || byte == '\n';
}

static bool uart_trace_has_terminal_marker(void)
{
    FILE *file;
    char line[512];
    unsigned int progress = 0;

    if (!uart_trace_path) {
        return false;
    }
    file = fopen(uart_trace_path, "r");
    if (!file) {
        return false;
    }
    while (fgets(line, sizeof(line), file)) {
        unsigned int value;
        const char *data_field;
        if (!strstr(line, "\"kind\":\"uart\"") ||
            !strstr(line, "\"write\":true")) {
            continue;
        }
        data_field = strstr(line, "\"data\":\"0x");
        if (!data_field || sscanf(data_field,
                   "\"data\":\"0x%x", &value) != 1) {
            continue;
        }
        /* The modeled UART presents text lines as CRLF even though the guest
         * marker contract is written with LF. Treat the CR immediately before
         * the marker newline as transport framing, not marker data. */
        if ((uint8_t)value == '\r' &&
            progress == sizeof(terminal_marker) - 2) {
            continue;
        }
        if ((uint8_t)value == (uint8_t)terminal_marker[progress]) {
            ++progress;
        } else if ((uint8_t)value == (uint8_t)terminal_marker[0]) {
            progress = 1;
        } else {
            progress = 0;
        }
        if (progress == sizeof(terminal_marker) - 1) {
            fclose(file);
            return true;
        }
    }
    fclose(file);
    return false;
}

static bool is_uart_register(uint64_t address, uint32_t offset)
{
    uint32_t addr = (uint32_t)address;
    uint32_t base = addr & 0xfffff000U;

    /* QEMU reports virtual addresses on some targets and physical addresses
     * on others. Accept only the Linux image's physical UART and aliases. */
    return (addr & 0xfffU) == offset &&
            (base == 0x04000000U || base == 0x04001000U ||
            base == 0x40000000U || base == 0xa0000000U ||
            base == 0xa4000000U || base == 0xa4001000U ||
            base == 0xc0000000U || base == 0xc0001000U);
}

static bool is_terminal_uart_tx(uint64_t address)
{
    return is_uart_register(address, 0);
}

static bool is_mdu_trace_instruction(uint32_t instr)
{
    uint32_t opcode = instr >> 26;
    uint32_t funct = instr & 0x3f;

    if (opcode == 0) {
        return funct == 0x10 || funct == 0x11 || funct == 0x12 ||
               funct == 0x13 || (funct >= 0x18 && funct <= 0x1b);
    }
    return opcode == 0x1c &&
           (funct == 0x00 || funct == 0x01 || funct == 0x02 ||
            funct == 0x04 || funct == 0x05);
}

static bool read_state_u32(const char *name, uint32_t *value)
{
    if (!state_registers) {
        return false;
    }
    for (guint i = 0; i < state_registers->len; ++i) {
        StateRegister *reg = g_ptr_array_index(state_registers, i);
        if (g_strcmp0(reg->name, name) == 0) {
            g_autoptr(GByteArray) bytes = g_byte_array_new();
            int size = qemu_plugin_read_register(reg->handle, bytes);
            if (size != 4) {
                return false;
            }
            *value = 0;
            for (int b = size - 1; b >= 0; --b) {
                *value = (*value << 8) | bytes->data[b];
            }
            return true;
        }
    }
    return false;
}

static void emit_mdu_trace(unsigned int cpu_index, InsnInfo *insn)
{
    uint32_t rs = (insn->instr >> 21) & 0x1f;
    uint32_t rt = (insn->instr >> 16) & 0x1f;
    uint32_t hi = 0, lo = 0, rs_value = 0, rt_value = 0;
    char rs_name[8], rt_name[8];
    unsigned valid;

    (void)cpu_index;
    if (!mdu_trace_file || !is_mdu_trace_instruction(insn->instr)) {
        return;
    }
    valid = read_state_u32("hi", &hi) ? 1U : 0U;
    valid |= read_state_u32("lo", &lo) ? 2U : 0U;
    g_snprintf(rs_name, sizeof(rs_name), "r%u", rs);
    g_snprintf(rt_name, sizeof(rt_name), "r%u", rt);
    valid |= read_state_u32(rs_name, &rs_value) ? 4U : 0U;
    valid |= read_state_u32(rt_name, &rt_value) ? 8U : 0U;
    fprintf(mdu_trace_file,
            "QEMU_MDU_TRACE record=%" PRIu64 " pc=%08" PRIx64
            " instr=%08" PRIx32 " rs=r%u:%08" PRIx32
            " rt=r%u:%08" PRIx32 " hi=%08" PRIx32
            " lo=%08" PRIx32 " valid=%x\n",
            record_count, insn->pc, insn->instr, rs, rs_value, rt, rt_value,
            hi, lo, valid);
    fflush(mdu_trace_file);
}

static void observe_terminal_uart(uint64_t address, uint8_t byte)
{
    unsigned int previous_progress = terminal_progress;
    if (!terminal_detection_enabled || terminal_marker_seen ||
        !is_terminal_uart_tx(address)) {
        return;
    }
    if (byte == '\r' && terminal_progress == sizeof(terminal_marker) - 2) {
        return;
    }
    if (byte == (uint8_t)terminal_marker[terminal_progress]) {
        ++terminal_progress;
    } else if (byte == (uint8_t)terminal_marker[0]) {
        terminal_progress = 1;
    } else {
        terminal_progress = 0;
    }
    if (debug_file) {
        fprintf(debug_file, "term addr=%08" PRIx64 " byte=%02x progress=%u->%u\n",
                address, byte, previous_progress, terminal_progress);
        fflush(debug_file);
    }
    if (terminal_progress == sizeof(terminal_marker) - 1) {
        terminal_marker_seen = true;
        terminal_progress = 0;
    }
}

static void report_terminal_record(void)
{
    if (terminal_record_reported) {
        return;
    }
    terminal_record_reported = true;
    terminal_record = record_count ? record_count - 1 : 0;
    if (status_file) {
        fprintf(status_file,
                "terminal_marker=flushed record=%" PRIu64 " uart_marker_bytes=%zu\n",
                terminal_record, sizeof(terminal_marker) - 1);
        fflush(status_file);
    }
}

static void report_capture_limit(const char *kind)
{
    if (capture_limit_reported) {
        return;
    }
    capture_limit_reported = true;
    qemu_plugin_outs("qemu retire plugin: capture limit reached; stopping record emission\n");
    if (status_file) {
        fprintf(status_file, "capture_limit=%s records=%" PRIu64 "\n", kind,
                record_count);
        fflush(status_file);
    }
}

static bool capture_limit_reached(void)
{
    if (record_count < max_records) {
        return false;
    }
    capture_stopped = true;
    report_capture_limit("records");
    return true;
}

static void vcpu_init(qemu_plugin_id_t id, unsigned int cpu_index)
{
    (void)id;
    g_autoptr(GArray) list = qemu_plugin_get_registers();
    if ((!register_file && !state_file && !mdu_trace_file) || cpu_index != 0) {
        return;
    }
    for (guint i = 0; i < list->len; ++i) {
        qemu_plugin_reg_descriptor *desc = &g_array_index(
            list, qemu_plugin_reg_descriptor, i);
        if (register_file) {
            fprintf(register_file, "%s\n", desc->name);
        }
        if ((state_file || mdu_trace_file) &&
            state_register_needed(desc->name)) {
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
        report_capture_limit("bytes");
        g_string_free(line, true);
        return;
    }
    if (write_record(state_file, state_is_fifo, line->str, line->len) != 0) {
        capture_stopped = true;
        g_string_free(line, true);
        return;
    }
    state_bytes += (uint64_t)line->len;
    g_free(last_state_line);
    last_state_line = g_strdup(line->str);
    g_string_free(line, true);
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
            "\",\"mem_value\":\"%08" PRIx32
            "\",\"mem_value_hi\":\"%08" PRIx32 "\",\"mem_size\":%u}\n",
            pending->pc, pending->instr, next_pc,
            pending->mem_valid, pending->mem_read, pending->mem_write,
            pending->mem_addr, pending->mem_value, pending->mem_value_hi,
            pending->mem_size);
    if (line_len < 0 || (size_t)line_len >= sizeof(line) ||
        trace_bytes > max_bytes || (uint64_t)line_len > max_bytes - trace_bytes) {
        capture_stopped = true;
        report_capture_limit("bytes");
        pending->valid = false;
        return;
    }
    if (write_record(trace_file, trace_is_fifo, line, (size_t)line_len) != 0) {
        capture_stopped = true;
        pending->valid = false;
        return;
    }
    trace_bytes += (uint64_t)line_len;
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
    struct qemu_plugin_hwaddr *hwaddr = qemu_plugin_get_hwaddr(info, vaddr);
    uint64_t device_addr = vaddr;

    if (hwaddr && qemu_plugin_hwaddr_is_io(hwaddr)) {
        device_addr = qemu_plugin_hwaddr_phys_addr(hwaddr);
    }

    pending->mem_valid = true;
    pending->mem_read = !qemu_plugin_mem_is_store(info);
    pending->mem_write = qemu_plugin_mem_is_store(info);
    pending->mem_addr = vaddr;
    pending->mem_size = 1u << qemu_plugin_mem_size_shift(info);
    switch (value.type) {
    case QEMU_PLUGIN_MEM_VALUE_U8: pending->mem_value = value.data.u8; break;
    case QEMU_PLUGIN_MEM_VALUE_U16: pending->mem_value = value.data.u16; break;
    case QEMU_PLUGIN_MEM_VALUE_U32: pending->mem_value = value.data.u32; break;
    case QEMU_PLUGIN_MEM_VALUE_U64:
        pending->mem_value = (uint32_t)value.data.u64;
        pending->mem_value_hi = (uint32_t)(value.data.u64 >> 32);
        break;
    case QEMU_PLUGIN_MEM_VALUE_U128:
        pending->mem_value = (uint32_t)value.data.u128.low;
        pending->mem_value_hi = (uint32_t)(value.data.u128.low >> 32);
        break;
    default: pending->mem_value = 0; break;
    }
    if (debug_file && pending->mem_read &&
        is_uart_register(device_addr, 5 * 4)) {
        uint64_t record = record_count ? record_count - 1 : 0;
        fprintf(debug_file,
                "uart_lsr record=%" PRIu64 " pc=%08" PRIx64
                " instr=%08" PRIx32 " addr=%08" PRIx64
                " value=%08" PRIx32 " size=%u\n",
                record, pending->pc, pending->instr, pending->mem_addr,
                pending->mem_value, pending->mem_size);
        fflush(debug_file);
    }
    if (pending->mem_write) {
        if (debug_file && is_terminal_uart_tx(device_addr) &&
            debug_marker_byte(pending->mem_value & 0xffU)) {
            fprintf(debug_file, "addr=%08" PRIx64 " value=%08" PRIx32
                    " size=%u byte=%02x\n", pending->mem_addr,
                    pending->mem_value, pending->mem_size,
                    pending->mem_value & 0xffU);
            fflush(debug_file);
        }
        observe_terminal_uart(device_addr, pending->mem_value & 0xffU);
    }
}

static void vcpu_insn_exec(unsigned int cpu_index, void *userdata)
{
    Pending *pending = &states[cpu_index];
    InsnInfo *insn = userdata;

    if (capture_stopped) {
        return;
    }
    if (capture_limit_reached()) {
        return;
    }
    emit_mdu_trace(cpu_index, insn);
    if (!summary_only) {
        emit_state(cpu_index, insn);
        emit_pending(pending, insn->pc);
    }
    ++record_count;
    if (terminal_marker_seen) {
        /* The pending record is the instruction that emitted the terminal
         * newline.  The state above is its flushed post-state boundary. */
        capture_stopped = true;
        report_terminal_record();
        return;
    }
    if (record_count >= max_records) {
        capture_stopped = true;
        report_capture_limit("records");
    }
    pending->pc = insn->pc;
    pending->instr = insn->instr;
    pending->valid = true;
    pending->mem_valid = false;
    pending->mem_read = false;
    pending->mem_write = false;
    pending->mem_addr = 0;
    pending->mem_value = 0;
    pending->mem_value_hi = 0;
    pending->mem_size = 0;
}

static void vcpu_exit(qemu_plugin_id_t id, unsigned int cpu_index)
{
    (void)id;
    if (summary_only) {
        return;
    }
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
                                               ((!summary_only && state_file) ||
                                                (mdu_trace_file &&
                                                 is_mdu_trace_instruction(
                                                     info->instr))) ?
                                               QEMU_PLUGIN_CB_R_REGS :
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
    if (states && !summary_only) {
        for (unsigned int i = 0; i < state_count; ++i) {
            emit_pending(&states[i], states[i].pc + 4);
            if (last_state_line) {
                /* plugin_exit has no current vCPU, so emit_state cannot read
                 * registers here. The terminal mailbox store has no state
                 * side effect; duplicating the last snapshot supplies the
                 * required post-state without violating plugin API rules. */
                write_record(state_file, state_is_fifo, last_state_line,
                             strlen(last_state_line));
            }
        }
    }
    if (terminal_detection_enabled && !terminal_record_reported &&
        !capture_limit_reported &&
        (terminal_marker_seen || uart_trace_has_terminal_marker())) {
        terminal_marker_seen = true;
        report_terminal_record();
    }
    fflush(trace_file);
    if (status_file && !capture_limit_reported && !terminal_record_reported) {
        fprintf(status_file, "capture_complete records=%" PRIu64 "\n", record_count);
        fflush(status_file);
    }
    fclose(trace_file);
    if (register_file) {
        fclose(register_file);
    }
    if (state_file) {
        fclose(state_file);
    }
    if (status_file) {
        fclose(status_file);
    }
    g_free(trace_path);
    g_free(register_path);
    g_free(state_path);
    g_free(status_path);
    if (debug_file) {
        fclose(debug_file);
    }
    if (mdu_trace_file) {
        fclose(mdu_trace_file);
    }
    if (fifo_write_mutex_initialized) {
        g_mutex_clear(&fifo_write_mutex);
        fifo_write_mutex_initialized = false;
    }
    g_free(debug_path);
    g_free(mdu_trace_path);
    g_free(uart_trace_path);
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
    g_mutex_init(&fifo_write_mutex);
    fifo_write_mutex_initialized = true;
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
            state_is_fifo = configure_output_buffering(state_file);
        } else if (g_strcmp0(tokens[0], "status") == 0 && tokens[1]) {
            g_free(status_path);
            status_path = g_strdup(tokens[1]);
            status_file = fopen(status_path, "w");
            if (!status_file) {
                fprintf(stderr, "qemu retire plugin: cannot open status output\n");
                return -1;
            }
        } else if (g_strcmp0(tokens[0], "debug") == 0 && tokens[1]) {
            g_free(debug_path);
            debug_path = g_strdup(tokens[1]);
            debug_file = fopen(debug_path, "w");
            if (!debug_file) {
                fprintf(stderr, "qemu retire plugin: cannot open debug output\n");
                return -1;
            }
        } else if (g_strcmp0(tokens[0], "mdu-trace") == 0 && tokens[1]) {
            g_free(mdu_trace_path);
            mdu_trace_path = g_strdup(tokens[1]);
            mdu_trace_file = fopen(mdu_trace_path, "w");
            if (!mdu_trace_file) {
                fprintf(stderr, "qemu retire plugin: cannot open MDU trace output\n");
                return -1;
            }
        } else if (g_strcmp0(tokens[0], "fpr-state") == 0 && tokens[1]) {
            if (g_strcmp0(tokens[1], "1") != 0 &&
                g_strcmp0(tokens[1], "0") != 0) {
                fprintf(stderr, "qemu retire plugin: fpr-state must be 0 or 1\n");
                return -1;
            }
            capture_fpr_state = g_strcmp0(tokens[1], "1") == 0;
        } else if (g_strcmp0(tokens[0], "uart-trace") == 0 && tokens[1]) {
            g_free(uart_trace_path);
            uart_trace_path = g_strdup(tokens[1]);
        } else if (g_strcmp0(tokens[0], "terminal-marker") == 0 && tokens[1]) {
            if (g_strcmp0(tokens[1], "linux") != 0) {
                fprintf(stderr, "qemu retire plugin: terminal-marker must be linux\n");
                return -1;
            }
            terminal_detection_enabled = true;
        } else if (g_strcmp0(tokens[0], "max-records") == 0 && tokens[1]) {
            char *end = NULL;
            errno = 0;
            max_records = g_ascii_strtoull(tokens[1], &end, 10);
            if (errno != 0 || end == tokens[1] || *end != '\0') {
                fprintf(stderr, "qemu retire plugin: max-records must be a non-negative integer\n");
                return -1;
            }
            if (max_records == 0)
                max_records = UINT64_MAX;
        } else if (g_strcmp0(tokens[0], "max-bytes") == 0 && tokens[1]) {
            char *end = NULL;
            errno = 0;
            max_bytes = g_ascii_strtoull(tokens[1], &end, 10);
            if (errno != 0 || end == tokens[1] || *end != '\0') {
                fprintf(stderr, "qemu retire plugin: max-bytes must be a non-negative integer\n");
                return -1;
            }
            if (max_bytes == 0)
                max_bytes = UINT64_MAX;
        } else if (g_strcmp0(tokens[0], "summary-only") == 0 && tokens[1]) {
            if (g_strcmp0(tokens[1], "1") != 0) {
                fprintf(stderr, "qemu retire plugin: summary-only must be 1\n");
                return -1;
            }
            summary_only = true;
        } else {
            fprintf(stderr, "qemu retire plugin: expected trace=/path, state=/path, status=/path, debug=/path, mdu-trace=/path, fpr-state=0|1, uart-trace=/path, terminal-marker=linux, max-records=N, max-bytes=N or summary-only=1, got %s\n", argv[i]);
            return -1;
        }
    }
    if (!trace_path || !(trace_file = fopen(trace_path, "w"))) {
        fprintf(stderr, "qemu retire plugin: cannot open trace output\n");
        return -1;
    }
    trace_is_fifo = configure_output_buffering(trace_file);
    state_count = info->system_emulation ? info->system.max_vcpus : 1;
    states = g_new0(Pending, state_count);
    if (state_file || mdu_trace_file) {
        state_registers = g_ptr_array_new();
    }
    qemu_plugin_register_vcpu_exit_cb(id, vcpu_exit);
    qemu_plugin_register_vcpu_tb_trans_cb(id, vcpu_tb_trans);
    if (register_file || state_file || mdu_trace_file) {
        qemu_plugin_register_vcpu_init_cb(id, vcpu_init);
    }
    qemu_plugin_register_atexit_cb(id, plugin_exit, NULL);
    return 0;
}
