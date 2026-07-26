/* -----------------------------------------------------------------------------
 * print.c — UART print + mailbox exit helpers
 * -------------------------------------------------------------------------- */
#include "soc_addr.h"
#include "print.h"

void print_str(const char *str) {
    while (*str) {
        UART_TX_DATA = *str++;
    }
}

void print_hex(uint32_t val) {
    const char hex_chars[] = "0123456789ABCDEF";
    for (int i = 28; i >= 0; i -= 4) {
        UART_TX_DATA = hex_chars[(val >> i) & 0xF];
    }
    UART_TX_DATA = '\n';
}

void mailbox_exit(void) {
    *MAILBOX_EXIT = MAILBOX_MAGIC;
    while (1) { /* halt */ }
}
