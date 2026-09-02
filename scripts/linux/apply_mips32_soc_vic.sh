#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
LINUX_SOURCE_DIR=${LINUX_SOURCE_DIR:-"${ROOT_DIR}/third_party/linux"}
DRIVER_SOURCE=${ROOT_DIR}/tb/linux_boot/irq-mips32-soc-vic.c

test -f "${LINUX_SOURCE_DIR}/drivers/irqchip/Kconfig"
test -f "${LINUX_SOURCE_DIR}/drivers/irqchip/Makefile"
test -f "${DRIVER_SOURCE}"

install -m 0644 "${DRIVER_SOURCE}" \
    "${LINUX_SOURCE_DIR}/drivers/irqchip/irq-mips32-soc-vic.c"

if ! rg -q '^config MIPS32_SOC_VIC$' \
    "${LINUX_SOURCE_DIR}/drivers/irqchip/Kconfig"; then
    sed -i '/^config GOLDFISH_PIC$/i\
config MIPS32_SOC_VIC\
\tbool "MIPS32 SoC reference vectored interrupt controller"\
\tdepends on MIPS && OF && HAS_IOMEM\
\tselect IRQ_DOMAIN\
\thelp\
\t  Enable the 32-source cascaded interrupt controller used by the\
\t  mips32-soc-ref reference machine.\
' "${LINUX_SOURCE_DIR}/drivers/irqchip/Kconfig"
fi

if ! rg -q 'irq-mips32-soc-vic\.o' \
    "${LINUX_SOURCE_DIR}/drivers/irqchip/Makefile"; then
    sed -i '/obj-\$(CONFIG_GOLDFISH_PIC)/a\obj-$(CONFIG_MIPS32_SOC_VIC)\t\t+= irq-mips32-soc-vic.o' \
        "${LINUX_SOURCE_DIR}/drivers/irqchip/Makefile"
fi
