/*
 * Small QEMU plugin for Linux RTL bring-up diagnostics.
 *
 * The regular retire plugin snapshots every QEMU register for every
 * instruction.  That is useful for short differential tests but too large
 * for a long Linux boot.  This plugin records only transitions of r30 and a
 * configurable PC window, with the register value before and after each
 * instruction.
 */
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
    uint64_t pc;
    uint32_t instr;
    uint32_t r30_before;
    bool valid;
} PreviousInsn;

static FILE *out;
static struct qemu_plugin_register *r30_handle;
static PreviousInsn previous;
static uint32_t focus_value = 0x89508405U;
static uint32_t focus_start = 0x88a35000U;
static uint32_t focus_end = 0x88a40000U;
static uint64_t records;
static uint64_t max_records = 4096;
static bool entry_only;

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

static bool pc_in_focus(uint64_t pc)
{
    return pc >= focus_start && pc <= focus_end;
}

/* Conservative decoder: false positives are harmless because the plugin is
 * diagnostic-only, while missing a possible r30 producer would hide the
 * transition being investigated. */
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

static bool read_r30(uint32_t *value)
{
    g_autoptr(GByteArray) bytes = g_byte_array_new();
    int size;

    if (!r30_handle) {
        return false;
    }
    size = qemu_plugin_read_register(r30_handle, bytes);
    if (size <= 0 || bytes->len < 4) {
        return false;
    }
    *value = ((uint32_t)bytes->data[0] << 24) |
             ((uint32_t)bytes->data[1] << 16) |
             ((uint32_t)bytes->data[2] << 8) |
             (uint32_t)bytes->data[3];
    return true;
}

static void emit_previous(uint32_t r30_after)
{
    bool interesting;

    if (!previous.valid || !out || records >= max_records) {
        return;
    }
    interesting = ((!entry_only && pc_in_focus(previous.pc)) ||
                   (entry_only && previous.pc == focus_start)) ||
                  (may_write_r30(previous.instr) &&
                   (previous.r30_before == focus_value ||
                    r30_after == focus_value));
    if (!interesting) {
        return;
    }
    fprintf(out,
            "QEMU_GPR_FOCUS pc=%08" PRIx64 " instr=%08" PRIx32
            " r30_before=%08" PRIx32 " r30_after=%08" PRIx32 "\n",
            previous.pc, previous.instr, previous.r30_before, r30_after);
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
        if (strcmp(desc->name, "r30") == 0) {
            r30_handle = desc->handle;
            break;
        }
    }
    if (!r30_handle) {
        fprintf(stderr, "qemu gpr focus: QEMU did not expose r30\n");
        exit(EXIT_FAILURE);
    }
}

static void vcpu_insn_exec(unsigned int cpu_index, void *userdata)
{
    uint32_t r30_before;
    uint32_t *encoded = userdata;
    (void)cpu_index;
    if (!read_r30(&r30_before)) {
        return;
    }
    emit_previous(r30_before);
    previous.pc = encoded[0];
    previous.instr = encoded[1];
    previous.r30_before = r30_before;
    previous.valid = true;
}

static void vcpu_tb_trans(qemu_plugin_id_t id, struct qemu_plugin_tb *tb)
{
    (void)id;
    for (size_t i = 0; i < qemu_plugin_tb_n_insns(tb); ++i) {
        struct qemu_plugin_insn *insn = qemu_plugin_tb_get_insn(tb, i);
        uint32_t *encoded = g_new0(uint32_t, 2);
        encoded[0] = (uint32_t)qemu_plugin_insn_vaddr(insn);
        qemu_plugin_insn_data(insn, &encoded[1], sizeof(encoded[1]));
        qemu_plugin_register_vcpu_insn_exec_cb(
            insn, vcpu_insn_exec, QEMU_PLUGIN_CB_R_REGS, encoded);
    }
}

static void plugin_exit(qemu_plugin_id_t id, void *userdata)
{
    uint32_t r30_after;
    (void)id;
    (void)userdata;
    if (read_r30(&r30_after)) {
        emit_previous(r30_after);
    }
    if (out) {
        fclose(out);
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
