/* Freestanding SoC port for the official Dhrystone 2.1 sources. */
#ifndef DHRYSTONE_PORT_H
#define DHRYSTONE_PORT_H

#include <stdint.h>

#ifndef DHRY_RUNS
#define DHRY_RUNS 100
#endif

long dhrystone_ticks(void);
void dhrystone_complete(int valid, long cycles);
char *malloc(unsigned long size);
char *strcpy(char *dst, const char *src);
int strcmp(const char *lhs, const char *rhs);
int printf(const char *fmt, ...);
int scanf(const char *fmt, ...);

#endif
