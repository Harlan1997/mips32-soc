/* -----------------------------------------------------------------------------
 * print.h — minimal UART print helpers used by all firmware variants
 * -------------------------------------------------------------------------- */
#ifndef PRINT_H
#define PRINT_H

#include <stdint.h>

void print_str(const char *str);
void print_hex(uint32_t val);
void mailbox_exit(void);   /* write success magic + halt */

#endif
