#include <stdint.h>
#include "print.h"
#define REG32(a) (*(volatile uint32_t *)(a))
#define DDR4_STATUS 0x40006000
int main(void) {
    uint32_t status = REG32(DDR4_STATUS + 4);
    uint32_t version = REG32(DDR4_STATUS + 0);
    uint32_t error = REG32(DDR4_STATUS + 8);
    if (version != 0x44445201 || (status & 7) != 7 || error != 0) {
        print_str("ddr4_status: FAIL\n");
        print_hex(version); print_hex(status); print_hex(error); print_str("\n");
        REG32(0xA000FFFC) = 0xDEADDEAD;
        while (1) { }
    }
    print_str("ddr4_status: REGRESSION_TEST_SUCCESS\n");
    mailbox_exit();
    return 0;
}
