#include <assert.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mips32_soc_uart_timing.h"

static uint16_t uart_divisor(uint8_t dll, uint8_t dlm)
{
    return (uint16_t)dll | ((uint16_t)dlm << 8);
}

static void run_schedule(const char *path)
{
    FILE *schedule = fopen(path, "r");
    SocRefUartTxModel tx = {0};
    SocRefUartModemModel modem;
    uint8_t ier = 0;
    uint8_t fcr = 0;
    uint8_t lcr = 0x03;
    uint8_t mcr = 0;
    uint8_t dll = 1;
    uint8_t dlm = 0;
    char line[256];
    uint64_t count = 0;
    uint64_t lsr_reads = 0;
    uint64_t cycle = 0;

    assert(schedule != NULL);
    soc_ref_uart_modem_reset(&modem,
                             SOC_REF_UART_MODEM_INPUTS_DEFAULT);
    while (fgets(line, sizeof(line), schedule)) {
        unsigned long long parsed_cycle;
        unsigned write;
        unsigned address;
        unsigned data;
        unsigned reg;

        if (line[0] == '#' || line[0] == '\n') {
            continue;
        }
        if (sscanf(line, "%llu %u %x %x", &parsed_cycle, &write,
                   &address, &data) != 4 || write > 1 ||
            address < 0x04000000U || address > 0x0400001cU ||
            (address & 3U)) {
            fprintf(stderr, "invalid UART APB schedule line: %s", line);
            abort();
        }
        cycle = parsed_cycle;
        reg = (address - 0x04000000U) >> 2;
        if (cycle <= tx.cycle) {
            fprintf(stderr, "non-increasing schedule cycle at event=%" PRIu64
                    " cycle=%" PRIu64 " model_cycle=%" PRIu64 "\n",
                    count, cycle, tx.cycle);
            abort();
        }
        soc_ref_uart_tx_advance_before(&tx, cycle, lcr,
                                       uart_divisor(dll, dlm), fcr, mcr,
                                       false);
        soc_ref_uart_modem_update(&modem, mcr);
        if (!write) {
            if (reg == 5) {
                uint32_t value = soc_ref_uart_tx_lsr_status(&tx);

                ++lsr_reads;
                if (((value ^ data) & 0x60U) != 0) {
                    fprintf(stderr,
                            "UART APB replay mismatch event=%" PRIu64
                            " cycle=%" PRIu64 " expected=%02x modeled=%02x"
                            " tx_state=%u baud_count=%u baud_tick=%u"
                            " pending=%zu\n",
                            count, cycle, data & 0x60U, value & 0x60U,
                            tx.tx_state, tx.baud_count, tx.baud16_tick,
                            tx.pending_count);
                    fclose(schedule);
                    exit(EXIT_FAILURE);
                }
            } else if (reg == 6) {
                uint8_t value = soc_ref_uart_modem_read(&modem, mcr);

                if (value != (uint8_t)data) {
                    fprintf(stderr,
                            "UART APB MSR replay mismatch event=%" PRIu64
                            " cycle=%" PRIu64 " expected=%02x modeled=%02x\n",
                            count, cycle, data & 0xffU, value);
                    fclose(schedule);
                    exit(EXIT_FAILURE);
                }
            }
            soc_ref_uart_tx_step(&tx, cycle, lcr, uart_divisor(dll, dlm),
                                 fcr, mcr, false, false, 0, false);
        } else if (reg == 0 && !(lcr & 0x80U)) {
            soc_ref_uart_tx_step(&tx, cycle, lcr, uart_divisor(dll, dlm),
                                 fcr, mcr, false, true,
                                 (uint8_t)data, false);
        } else if (reg == 2) {
            soc_ref_uart_tx_step(&tx, cycle, lcr, uart_divisor(dll, dlm),
                                 fcr, mcr, false, false, 0,
                                 (data & 0x04U) != 0);
            fcr = data & 0xc1U;
        } else {
            soc_ref_uart_tx_step(&tx, cycle, lcr, uart_divisor(dll, dlm),
                                 fcr, mcr, false, false, 0, false);
            if (reg == 0 && (lcr & 0x80U)) {
                dll = data & 0xffU;
            } else if (reg == 1 && (lcr & 0x80U)) {
                dlm = data & 0xffU;
            } else if (reg == 1) {
                ier = data & 0x0fU;
            } else if (reg == 3) {
                lcr = data & 0xffU;
            } else if (reg == 4) {
                mcr = data & 0xffU;
                soc_ref_uart_modem_update(&modem, mcr);
            }
        }
        ++count;
        (void)ier;
    }
    fclose(schedule);
    printf("MIPS32_SOC_UART_SCHEDULE_REPLAY_PASS events=%" PRIu64
           " lsr_reads=%" PRIu64 " last_cycle=%" PRIu64 "\n",
           count, lsr_reads, cycle);
}

static void test_uart_modem_status(void)
{
    SocRefUartModemModel modem;

    soc_ref_uart_modem_reset(&modem, SOC_REF_UART_MODEM_INPUTS_DEFAULT);
    assert(soc_ref_uart_modem_read(&modem, 0) == 0xbbU);
    assert(soc_ref_uart_modem_read(&modem, 0) == 0xb0U);

    soc_ref_uart_modem_reset(&modem, 0x0fU);
    assert(soc_ref_uart_modem_read(&modem, 0) == 0x00U);
    modem.input_n = 0x00U;
    assert(soc_ref_uart_modem_read(&modem, 0) == 0xffU);
    assert(soc_ref_uart_modem_read(&modem, 0) == 0xf0U);
    modem.input_n = 0x0fU;
    assert(soc_ref_uart_modem_read(&modem, 0) == 0x0bU);

    soc_ref_uart_modem_reset(&modem, 0x0fU);
    assert(soc_ref_uart_modem_read(&modem, 0x10U) == 0x00U);
    assert(soc_ref_uart_modem_read(&modem, 0x1fU) == 0xffU);
    assert(soc_ref_uart_modem_read(&modem, 0x1fU) == 0xf0U);
}

static void test_cycle_interpolation(void)
{
    const SocRefCpuCycleSample samples[] = {
        { .retire_seq = 0, .cycle = 100 },
        { .retire_seq = 16, .cycle = 140 },
        { .retire_seq = 32, .cycle = 200 },
    };
    size_t cursor = 0;

    assert(soc_ref_cpu_cycle_at_retire(samples, 3, 8, &cursor) == 120);
    assert(soc_ref_cpu_cycle_at_retire(samples, 3, 24, &cursor) == 170);
    assert(soc_ref_cpu_cycle_at_retire(samples, 3, 40, &cursor) == 230);
    assert(soc_ref_cpu_cycle_at_retire(samples, 3, 8, &cursor) == 120);
}

static void test_uart_tx_edges(void)
{
    SocRefUartTxModel tx = {0};
    uint32_t value;

    assert(soc_ref_uart_tx_lsr_status(&tx) == SOC_REF_UART_LSR_TEMT);
    assert(soc_ref_uart_tx_step(&tx, 1, 0x03, 1, 0, 0, false,
                                true, 0x41, false));
    assert(soc_ref_uart_tx_lsr_status(&tx) == 0);

    soc_ref_uart_tx_advance_before(&tx, 2, 0x03, 1, 0, 0, false);
    soc_ref_uart_tx_step(&tx, 2, 0x03, 1, 0, 0, false, false, 0, false);
    assert(soc_ref_uart_tx_lsr_status(&tx) == SOC_REF_UART_LSR_THRE);

    soc_ref_uart_tx_advance_before(&tx, 161, 0x03, 1, 0, 0, false);
    assert(soc_ref_uart_tx_lsr_status(&tx) == SOC_REF_UART_LSR_THRE);
    soc_ref_uart_tx_advance_before(&tx, 162, 0x03, 1, 0, 0, false);
    assert(soc_ref_uart_tx_lsr_status(&tx) == SOC_REF_UART_LSR_THRE);
    soc_ref_uart_tx_advance_before(&tx, 163, 0x03, 1, 0, 0, false);
    assert(soc_ref_uart_tx_lsr_status(&tx) == SOC_REF_UART_LSR_TEMT);

    tx = (SocRefUartTxModel){0};
    assert(soc_ref_uart_tx_step(&tx, 1, 0x03, 27, 0, 0, false,
                                true, 0x5b, false));
    soc_ref_uart_tx_advance_before(&tx, 2, 0x03, 27, 0, 0, false);
    soc_ref_uart_tx_step(&tx, 2, 0x03, 27, 0, 0, false, false, 0, false);
    value = soc_ref_uart_tx_lsr_status(&tx);
    assert(value == SOC_REF_UART_LSR_THRE);
    soc_ref_uart_tx_advance_before(&tx, 4500, 0x03, 27, 0, 0, false);
    assert(soc_ref_uart_tx_lsr_status(&tx) == SOC_REF_UART_LSR_TEMT);

    tx = (SocRefUartTxModel){0};
    assert(soc_ref_uart_tx_step(&tx, 1, 0x03, 1, 0x01, 0, false,
                                true, 0x41, false));
    assert(soc_ref_uart_tx_step(&tx, 2, 0x03, 1, 0x01, 0, false,
                                true, 0x42, false));
    assert(tx.pending_count == 1);
    assert(soc_ref_uart_tx_lsr_status(&tx) == 0);
    soc_ref_uart_tx_step(&tx, 3, 0x03, 1, 0x01, 0, false,
                         false, 0, true);
    assert(tx.pending_count == 0);
    assert(tx.active);
    assert(soc_ref_uart_tx_lsr_status(&tx) == SOC_REF_UART_LSR_THRE);
}

int main(int argc, char **argv)
{
    test_cycle_interpolation();
    test_uart_tx_edges();
    test_uart_modem_status();
    puts("MIPS32_SOC_UART_TIMING_TEST_PASS");
    if (argc == 2) {
        run_schedule(argv[1]);
    } else if (argc != 1) {
        fprintf(stderr, "usage: %s [uart-apb-schedule]\n", argv[0]);
        return EXIT_FAILURE;
    }
    return EXIT_SUCCESS;
}
