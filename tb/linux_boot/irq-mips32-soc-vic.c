// SPDX-License-Identifier: GPL-2.0-only
/*
 * MIPS32 SoC reference vectored interrupt controller.
 *
 * The controller is a 32-source cascaded PIC. Reading VEC_ID accepts the
 * highest-priority interrupt and writing ACK retires the active source.
 */
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/irq.h>
#include <linux/irqchip.h>
#include <linux/irqchip/chained_irq.h>
#include <linux/irqdomain.h>
#include <linux/of_address.h>
#include <linux/of_irq.h>

#define SOC_VIC_NR_IRQS    32
#define SOC_VIC_ENABLE_SET 0x00c
#define SOC_VIC_ENABLE_CLR 0x010
#define SOC_VIC_VEC_ID     0x200
#define SOC_VIC_ACK        0x208

struct soc_vic {
	void __iomem *base;
	struct irq_domain *domain;
};

static void soc_vic_mask(struct irq_data *d)
{
	struct soc_vic *vic = irq_data_get_irq_chip_data(d);

	writel(BIT(d->hwirq), vic->base + SOC_VIC_ENABLE_CLR);
}

static void soc_vic_unmask(struct irq_data *d)
{
	struct soc_vic *vic = irq_data_get_irq_chip_data(d);

	writel(BIT(d->hwirq), vic->base + SOC_VIC_ENABLE_SET);
}

static void soc_vic_ack(struct irq_data *d)
{
	struct soc_vic *vic = irq_data_get_irq_chip_data(d);

	writel(BIT(d->hwirq), vic->base + SOC_VIC_ACK);
}

static struct irq_chip soc_vic_chip = {
	.name = "mips32-soc-vic",
	.irq_ack = soc_vic_ack,
	.irq_mask = soc_vic_mask,
	.irq_unmask = soc_vic_unmask,
};

static int soc_vic_map(struct irq_domain *domain, unsigned int irq,
			       irq_hw_number_t hwirq)
{
	struct soc_vic *vic = domain->host_data;

	irq_set_chip_data(irq, vic);
	irq_set_chip_and_handler(irq, &soc_vic_chip, handle_level_irq);
	irq_set_noprobe(irq);
	return 0;
}

static const struct irq_domain_ops soc_vic_domain_ops = {
	.map = soc_vic_map,
	.xlate = irq_domain_xlate_onecell,
};

static void soc_vic_cascade(struct irq_desc *desc)
{
	struct soc_vic *vic = irq_desc_get_handler_data(desc);
	struct irq_chip *parent_chip = irq_desc_get_chip(desc);
	unsigned int hwirq;

	chained_irq_enter(parent_chip, desc);
	while ((hwirq = readl(vic->base + SOC_VIC_VEC_ID)) < SOC_VIC_NR_IRQS)
		generic_handle_domain_irq(vic->domain, hwirq);
	chained_irq_exit(parent_chip, desc);
}

static int __init soc_vic_of_init(struct device_node *node,
				  struct device_node *parent)
{
	struct soc_vic *vic;
	unsigned int parent_irq;

	vic = kzalloc(sizeof(*vic), GFP_KERNEL);
	if (!vic)
		return -ENOMEM;

	parent_irq = irq_of_parse_and_map(node, 0);
	if (!parent_irq) {
		pr_err("mips32-soc-vic: missing parent IRQ\n");
		kfree(vic);
		return -EINVAL;
	}

	vic->base = of_iomap(node, 0);
	if (!vic->base) {
		pr_err("mips32-soc-vic: unable to map registers\n");
		irq_dispose_mapping(parent_irq);
		kfree(vic);
		return -ENOMEM;
	}

	/* Start masked; Linux enables each child as its driver probes. */
	writel(~0U, vic->base + SOC_VIC_ENABLE_CLR);
	vic->domain = irq_domain_add_linear(node, SOC_VIC_NR_IRQS,
					    &soc_vic_domain_ops, vic);
	if (!vic->domain) {
		pr_err("mips32-soc-vic: unable to create IRQ domain\n");
		iounmap(vic->base);
		irq_dispose_mapping(parent_irq);
		kfree(vic);
		return -ENOMEM;
	}

	irq_set_chained_handler_and_data(parent_irq, soc_vic_cascade, vic);
	pr_info("mips32-soc-vic: 32-source cascaded controller on IRQ %u\n",
		parent_irq);
	return 0;
}

IRQCHIP_DECLARE(mips32_soc_vic, "harlan,mips32-soc-vic", soc_vic_of_init);
