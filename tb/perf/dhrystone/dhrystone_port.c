/* Copyright 2026 Harlan1997. SoC-specific freestanding validation port. */
#include "dhrystone_port.h"
#include "soc_addr.h"
#include <stdarg.h>

static unsigned char heap[512];
static unsigned long heap_used;

long dhrystone_ticks(void) {
    return (long)PERF_CYCLE_COUNT;
}

char *malloc(unsigned long size) {
    unsigned long aligned = (size + 3U) & ~3U;
    if (heap_used + aligned > sizeof(heap)) {
        return (char *)0;
    }
    char *result = (char *)&heap[heap_used];
    heap_used += aligned;
    return result;
}

char *strcpy(char *dst, const char *src) {
    char *result = dst;
    while ((*dst++ = *src++) != '\0') { }
    return result;
}

int strcmp(const char *lhs, const char *rhs) {
    while (*lhs && *lhs == *rhs) {
        ++lhs;
        ++rhs;
    }
    return (unsigned char)*lhs - (unsigned char)*rhs;
}

static void putc_uart(char value) {
    UART_TX_DATA = (uint32_t)(unsigned char)value;
}

static void puts_uart(const char *value) {
    while (*value) {
        putc_uart(*value++);
    }
}

static void put_unsigned(unsigned long value) {
    char buffer[11];
    unsigned int index = 0;
    if (value == 0) {
        putc_uart('0');
        return;
    }
    while (value && index < sizeof(buffer)) {
        buffer[index++] = (char)('0' + (value % 10U));
        value /= 10U;
    }
    while (index) {
        putc_uart(buffer[--index]);
    }
}

static void put_signed(long value) {
    if (value < 0) {
        putc_uart('-');
        put_unsigned((unsigned long)(-value));
    } else {
        put_unsigned((unsigned long)value);
    }
}

int printf(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    while (*fmt) {
        if (*fmt != '%') {
            putc_uart(*fmt++);
            continue;
        }
        ++fmt;
        while (*fmt == ' ' || (*fmt >= '0' && *fmt <= '9')) {
            ++fmt;
        }
        if (*fmt == 'l') {
            ++fmt;
        }
        switch (*fmt++) {
        case 'c': putc_uart((char)va_arg(args, int)); break;
        case 'd': put_signed((long)va_arg(args, int)); break;
        case 's': puts_uart(va_arg(args, const char *)); break;
        case '%': putc_uart('%'); break;
        default: putc_uart('?'); break;
        }
    }
    va_end(args);
    return 0;
}

int scanf(const char *fmt, ...) {
    va_list args;
    (void)fmt;
    va_start(args, fmt);
    *va_arg(args, int *) = DHRY_RUNS;
    va_end(args);
    return 1;
}

void dhrystone_complete(int valid, long cycles) {
    printf("Dhrystone validation: %s\n", valid ? "PASS" : "FAIL");
    printf("Dhrystone cycles: %ld\n", cycles);
    *MAILBOX_EXIT = MAILBOX_MAGIC;
    while (1) { }
}
