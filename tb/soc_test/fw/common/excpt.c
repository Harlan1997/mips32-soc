/* -----------------------------------------------------------------------------
 * excpt.c — minimal weak default exception handler for isolated firmwares.
 *
 * A firmware may override c_interrupt_handler with its own strong definition
 * for full-featured exception dispatch (e.g. peripheral IRQ + AdEL semantics).
 * This weak default just clears the timer IRQ if present, advances EPC on
 * synchronous exceptions, and exits via mailbox on AdEL — enough for CPU-only
 * smoke firmwares to make progress.
 * -------------------------------------------------------------------------- */
#include "soc_addr.h"
#include "print.h"

__attribute__((weak))
void c_interrupt_handler(void) {
    uint32_t cause;
    asm volatile("mfc0 %0, $13" : "=r"(cause));
    uint32_t exc_code = (cause >> 2) & 0x1F;

    if (exc_code == 4) {
        /* AdEL — treat as clean exit for CPU-only firmwares that use an
         * unaligned jump as their termination signal.
         */
        print_str("   AdEL EXIT\n");
        mailbox_exit();
    }

    if (exc_code == 0) {
        /* External interrupt — clear timer if that's the source. */
        uint32_t pic_act = PIC_ACTIVE;
        if (pic_act & 0x4) {
            TIMER_INTCLR = 1;
        }
        return;
    }

    /* Any other synchronous exception: advance past the faulting instruction
     * so we don't loop.
     */
    uint32_t epc;
    asm volatile("mfc0 %0, $14" : "=r"(epc));
    epc += 4;
    asm volatile("mtc0 %0, $14" : : "r"(epc));
}
