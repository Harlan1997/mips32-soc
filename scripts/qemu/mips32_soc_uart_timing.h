#ifndef MIPS32_SOC_UART_TIMING_H
#define MIPS32_SOC_UART_TIMING_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define SOC_REF_UART_LSR_THRE 0x20U
#define SOC_REF_UART_LSR_TEMT 0x60U
#define SOC_REF_UART_TX_FIFO_DEPTH 16U
#define SOC_REF_UART_MODEM_INPUTS_DEFAULT 0x08U

typedef struct SocRefUartModemModel {
    uint8_t input_n;
    uint8_t previous_n;
    uint8_t delta;
} SocRefUartModemModel;

typedef struct SocRefCpuCycleSample {
    uint64_t retire_seq;
    uint64_t cycle;
} SocRefCpuCycleSample;

typedef struct SocRefUartTxModel {
    uint8_t pending_data[SOC_REF_UART_TX_FIFO_DEPTH];
    size_t pending_head;
    size_t pending_count;
    uint64_t cycle;
    uint16_t baud_count;
    uint8_t tx_state;
    uint8_t tx_bit_count;
    uint8_t tx_bit_index;
    bool baud16_tick;
    bool active;
} SocRefUartTxModel;

enum SocRefUartTxState {
    SOC_REF_UART_TX_IDLE,
    SOC_REF_UART_TX_START,
    SOC_REF_UART_TX_DATA,
    SOC_REF_UART_TX_PARITY,
    SOC_REF_UART_TX_STOP1,
    SOC_REF_UART_TX_STOP2,
};

static inline uint8_t soc_ref_uart_modem_n(uint8_t input_n, uint8_t mcr)
{
    uint8_t modem_n = input_n & 0x0fU;

    if (mcr & 0x10U) {
        modem_n = ((mcr & 0x02U) ? 0U : 0x01U) |
                  ((mcr & 0x01U) ? 0U : 0x02U) |
                  ((mcr & 0x08U) ? 0U : 0x04U) |
                  ((mcr & 0x04U) ? 0U : 0x08U);
    }
    return modem_n;
}

static inline void soc_ref_uart_modem_reset(SocRefUartModemModel *model,
                                             uint8_t input_n)
{
    model->input_n = input_n & 0x0fU;
    model->previous_n = 0x0fU;
    model->delta = 0;
}

static inline void soc_ref_uart_modem_update(SocRefUartModemModel *model,
                                              uint8_t mcr)
{
    uint8_t modem_n = soc_ref_uart_modem_n(model->input_n, mcr);
    uint8_t changed = model->previous_n ^ modem_n;

    model->delta |= changed & 0x03U;
    model->delta |= (changed & 0x04U) << 1;
    if ((model->previous_n & 0x08U) && !(modem_n & 0x08U)) {
        model->delta |= 0x04U;
    }
    model->previous_n = modem_n;
}

static inline uint8_t soc_ref_uart_modem_read(SocRefUartModemModel *model,
                                               uint8_t mcr)
{
    uint8_t modem_n;
    uint8_t status = 0;

    soc_ref_uart_modem_update(model, mcr);
    modem_n = model->previous_n;
    if (!(modem_n & 0x01U)) status |= 0x10U;
    if (!(modem_n & 0x02U)) status |= 0x20U;
    if (!(modem_n & 0x08U)) status |= 0x40U;
    if (!(modem_n & 0x04U)) status |= 0x80U;
    status |= model->delta;
    model->delta = 0;
    return status;
}

static inline uint64_t soc_ref_cpu_cycle_at_retire(
    const SocRefCpuCycleSample *samples, size_t count, uint64_t retire_seq,
    size_t *cursor)
{
    size_t index = cursor ? *cursor : 0;
    const SocRefCpuCycleSample *first;
    const SocRefCpuCycleSample *last;
    uint64_t retire_delta;
    uint64_t cycle_delta;
    uint64_t offset;

    if (!samples || count == 0) {
        return 0;
    }
    if (index >= count - 1) {
        index = count - 1;
    }
    while (index > 0 && retire_seq < samples[index].retire_seq) {
        --index;
    }
    while (index + 1 < count && retire_seq > samples[index + 1].retire_seq) {
        ++index;
    }
    if (cursor) {
        *cursor = index;
    }
    if (count == 1) {
        return samples[0].cycle;
    }
    if (index + 1 == count) {
        first = &samples[count - 2];
        last = &samples[count - 1];
        retire_delta = last->retire_seq - first->retire_seq;
        cycle_delta = last->cycle - first->cycle;
        offset = retire_seq > last->retire_seq ?
            retire_seq - last->retire_seq : 0;
        return last->cycle + (retire_delta ?
            (offset * cycle_delta) / retire_delta : 0);
    }
    first = &samples[index];
    last = &samples[index + 1];
    retire_delta = last->retire_seq - first->retire_seq;
    cycle_delta = last->cycle - first->cycle;
    offset = retire_seq > first->retire_seq ?
        retire_seq - first->retire_seq : 0;
    return first->cycle + (retire_delta ?
        (offset * cycle_delta) / retire_delta : 0);
}

static inline unsigned soc_ref_uart_data_bits(uint8_t lcr)
{
    return 5U + (lcr & 0x3U);
}

static inline uint16_t soc_ref_uart_effective_divisor(uint16_t divisor)
{
    return divisor ? divisor : 1U;
}

static inline bool soc_ref_uart_tx_step(SocRefUartTxModel *model,
                                        uint64_t cycle, uint8_t lcr,
                                        uint16_t divisor, uint8_t fcr,
                                        uint8_t mcr, bool cts_n,
                                        bool write_thr, uint8_t thr_data,
                                        bool clear_fifo)
{
    bool accepted = false;

    if (cycle <= model->cycle) {
        return false;
    }

    if (write_thr) {
        size_t capacity = (fcr & 0x01U) ? SOC_REF_UART_TX_FIFO_DEPTH : 1U;

        accepted = model->pending_count < capacity;
    }

    if (model->tx_state == SOC_REF_UART_TX_IDLE) {
        bool cts_n_int = (mcr & 0x10U) ? !(mcr & 0x02U) : cts_n;
        bool cts_allowed = !(mcr & 0x20U) || !cts_n_int;

        if (model->pending_count && !(lcr & 0x40U) && cts_allowed) {
            model->pending_head =
                (model->pending_head + 1) % SOC_REF_UART_TX_FIFO_DEPTH;
            --model->pending_count;
            model->tx_state = SOC_REF_UART_TX_START;
            model->tx_bit_count = 0;
            model->tx_bit_index = 0;
            model->active = true;
        }
    } else if (model->baud16_tick) {
        if (model->tx_bit_count == 15U) {
            model->tx_bit_count = 0;
            switch (model->tx_state) {
            case SOC_REF_UART_TX_START:
                model->tx_bit_index = 1;
                model->tx_state = SOC_REF_UART_TX_DATA;
                break;
            case SOC_REF_UART_TX_DATA:
                if (model->tx_bit_index < soc_ref_uart_data_bits(lcr)) {
                    ++model->tx_bit_index;
                } else if (lcr & 0x08U) {
                    model->tx_state = SOC_REF_UART_TX_PARITY;
                } else {
                    model->tx_state = SOC_REF_UART_TX_STOP1;
                }
                break;
            case SOC_REF_UART_TX_PARITY:
                model->tx_state = SOC_REF_UART_TX_STOP1;
                break;
            case SOC_REF_UART_TX_STOP1:
                model->tx_state = (lcr & 0x04U) ?
                    SOC_REF_UART_TX_STOP2 : SOC_REF_UART_TX_IDLE;
                break;
            case SOC_REF_UART_TX_STOP2:
            default:
                model->tx_state = SOC_REF_UART_TX_IDLE;
                break;
            }
            model->active = model->tx_state != SOC_REF_UART_TX_IDLE;
        } else {
            ++model->tx_bit_count;
        }
    }

    divisor = soc_ref_uart_effective_divisor(divisor);
    if (model->baud_count >= divisor - 1U) {
        model->baud_count = 0;
        model->baud16_tick = true;
    } else {
        ++model->baud_count;
        model->baud16_tick = false;
    }

    if (clear_fifo) {
        model->pending_head = 0;
        model->pending_count = 0;
    } else if (write_thr && accepted) {
        size_t tail = (model->pending_head + model->pending_count) %
                      SOC_REF_UART_TX_FIFO_DEPTH;

        model->pending_data[tail] = thr_data;
        ++model->pending_count;
    }
    model->cycle = cycle;
    return accepted;
}

static inline bool soc_ref_uart_tx_idle_blocked(
    const SocRefUartTxModel *model, uint8_t lcr, uint8_t mcr, bool cts_n)
{
    bool cts_n_int = (mcr & 0x10U) ? !(mcr & 0x02U) : cts_n;
    bool cts_allowed = !(mcr & 0x20U) || !cts_n_int;

    return model->tx_state == SOC_REF_UART_TX_IDLE &&
           (model->pending_count == 0 || (lcr & 0x40U) || !cts_allowed);
}

static inline void soc_ref_uart_tx_skip_idle(
    SocRefUartTxModel *model, uint64_t last_cycle, uint8_t lcr,
    uint16_t divisor, uint8_t mcr, bool cts_n)
{
    uint64_t cycles = last_cycle - model->cycle;
    uint64_t first_tick;
    uint64_t remainder;

    if (!cycles || !soc_ref_uart_tx_idle_blocked(model, lcr, mcr, cts_n)) {
        return;
    }
    divisor = soc_ref_uart_effective_divisor(divisor);
    first_tick = (uint64_t)divisor - model->baud_count;
    if (cycles < first_tick) {
        model->baud_count += (uint16_t)cycles;
        model->baud16_tick = false;
    } else {
        remainder = (cycles - first_tick) % divisor;
        model->baud_count = (uint16_t)remainder;
        model->baud16_tick = remainder == 0;
    }
    model->cycle = last_cycle;
}

static inline void soc_ref_uart_tx_advance_before(
    SocRefUartTxModel *model, uint64_t cycle, uint8_t lcr,
    uint16_t divisor, uint8_t fcr, uint8_t mcr, bool cts_n)
{
    uint64_t last_cycle = cycle ? cycle - 1 : 0;

    while (model->cycle < last_cycle) {
        uint64_t before = model->cycle;

        soc_ref_uart_tx_skip_idle(model, last_cycle, lcr, divisor, mcr,
                                  cts_n);
        if (model->cycle == before) {
            soc_ref_uart_tx_step(model, model->cycle + 1, lcr, divisor, fcr,
                                 mcr, cts_n, false, 0, false);
        }
    }
}

static inline void soc_ref_uart_tx_advance_through(
    SocRefUartTxModel *model, uint64_t cycle, uint8_t lcr,
    uint16_t divisor, uint8_t fcr, uint8_t mcr, bool cts_n)
{
    while (model->cycle < cycle) {
        uint64_t before = model->cycle;

        soc_ref_uart_tx_skip_idle(model, cycle, lcr, divisor, mcr, cts_n);
        if (model->cycle == before) {
            soc_ref_uart_tx_step(model, model->cycle + 1, lcr, divisor, fcr,
                                 mcr, cts_n, false, 0, false);
        }
    }
}

static inline void soc_ref_uart_tx_clear_pending(SocRefUartTxModel *model)
{
    model->pending_head = 0;
    model->pending_count = 0;
}

static inline uint32_t soc_ref_uart_tx_lsr_status(
    const SocRefUartTxModel *model)
{
    uint32_t status = 0;

    if (model->pending_count == 0) {
        status |= SOC_REF_UART_LSR_THRE;
        if (!model->active) {
            status |= SOC_REF_UART_LSR_TEMT & ~SOC_REF_UART_LSR_THRE;
        }
    }
    return status;
}

static inline bool soc_ref_uart_tx_irq_pending(
    const SocRefUartTxModel *model, uint8_t ier)
{
    return (ier & 0x02U) != 0 && model->pending_count == 0;
}

static inline uint8_t soc_ref_uart_iir_status(
    const SocRefUartTxModel *model, uint8_t ier, uint8_t fcr)
{
    uint8_t fifo_bits = (fcr & 0x01U) ? 0xc0U : 0;
    uint8_t interrupt_id = soc_ref_uart_tx_irq_pending(model, ier) ? 0x02U :
                                                                      0x01U;

    return fifo_bits | interrupt_id;
}

#endif
