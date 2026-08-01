/*
 * WDT boot-failure firmware gate.
 *
 * First entry records a diagnostic stage/code and arms the APB watchdog. The
 * watchdog resets the CPU/SoC fabric, but boot-status remains in the
 * always-on domain. The reset entry then validates the retained record and
 * reset cause before completing through the normal mailbox contract.
 */
#include <stdint.h>
#include "print.h"

#define REG32(addr) (*(volatile uint32_t *)(addr))

#define WDT_BASE       0x40007000u
#define WDT_CTRL       (WDT_BASE + 0x00u)
#define WDT_LOAD       (WDT_BASE + 0x04u)
#define WDT_STATUS     (WDT_BASE + 0x10u)

#define BOOT_STATUS_BASE 0x40008000u
#define BOOT_STAGE       (BOOT_STATUS_BASE + 0x00u)
#define BOOT_FAILURE     (BOOT_STATUS_BASE + 0x04u)
#define RESET_CAUSE      (BOOT_STATUS_BASE + 0x08u)

#define STAGE_HEADER_CHECK 0x20u
#define STAGE_HANDOFF      0x70u
#define FAILURE_TIMEOUT    0xB0070001u

static void mailbox_fail(uint32_t code) {
    (void)code;
    *((volatile uint32_t *)0xA000FFFCu) = 0xDEADDEADu;
    while (1) { }
}

int main(void) {
    uint32_t cause = REG32(RESET_CAUSE);

    if ((cause & 0x2u) == 0) {
        // POR is the only expected cause on the first entry. Record the
        // failure before arming the watchdog and deliberately stop petting it.
        if ((cause & 0x1u) == 0)
            mailbox_fail(cause);
        REG32(BOOT_STAGE) = STAGE_HEADER_CHECK;
        REG32(BOOT_FAILURE) = FAILURE_TIMEOUT;
        REG32(WDT_LOAD) = 4u;
        REG32(WDT_CTRL) = 1u;
        while (1) { }
    }

    // The watchdog reset must preserve all diagnostics and identify itself.
    if ((cause & 0x3u) != 0x3u ||
        REG32(BOOT_STAGE) != STAGE_HEADER_CHECK ||
        REG32(BOOT_FAILURE) != FAILURE_TIMEOUT) {
        mailbox_fail(cause);
    }

    REG32(WDT_STATUS) = 1u;
    REG32(BOOT_STAGE) = STAGE_HANDOFF;
    REG32(BOOT_FAILURE) = 0u;
    REG32(RESET_CAUSE) = 0x3u;
    print_str("wdt_boot_failure: REGRESSION_TEST_SUCCESS\n");
    mailbox_exit();
    return 0;
}
