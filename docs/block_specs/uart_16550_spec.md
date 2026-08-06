# UART 16550 兼容控制器 微架构规格 (v2 - Phase 4E Commercial Hardening)

> 状态：Phase 4E 已闭合当前商业级 DUT 合同。`rtl/perips/apb_uart_16550.v` 已通过单元测试门禁 (`make dut-block-unit-gate`) 以及 SoC APB CPU 固件门禁 (`make uart-cpu-gate`)。
> 注意：Linux 8250 驱动完整兼容性、实板波特率容差、CDC/RDC、Formal 证明与完整 CTS/RTS 硬件流控仍属于后续系统级验证目标。

---

## 0. 目标与闭合范围

### Phase 4E 已闭合合同范围:
- **APB 协议**: `pready = 1`, `pslverr = 0`, 非合法/保留地址读返回 0。支持 `pstrb[3:0]` 字节通道选择。
- **PC16550D 寄存器映射**:
  - DLAB (LCR[7]): 控制 0x00 (DLL vs RBR/THR) 与 0x04 (DLM vs IER) 访问分离。
  - SCR (0x1C): 8-bit 可读写 scratchpad 寄存器。
  - IER / IIR: 4 级中断使能与硬编码优先级编码；IIR[7:6] 准确反映 FCR FIFO 使能状态 (11 为使能, 00 为禁用)。
  - FCR: 支持 FIFO 模式与单字节兼容模式；FCR[2:1] 复位位具有自清零 (self-clearing) 语义。
  - LSR: DR, OE, PE, FE, BI, THRE, TEMT, RFE (LSR[7])；读 LSR 清零 OE；读 RBR 弹出 Head 字符及关联错误位。
  - MSR / Modem Loopback: MCR.LOOP 环回 mapping (DTR→DSR, RTS→CTS, OUT1→RI, OUT2→DCD)；MSR 4 字节 delta 位锁存并在读 MSR 时清零。
- **FIFO 使能与禁用模式**:
  - FIFO 使能 (`FCR[0]=1`): 16 项 TX/RX FIFO，触发阈值 1 / 4 / 8 / 14 字符。
  - FIFO 禁用 (`FCR[0]=0`): 1 字符单字节兼容模式，未读字符在后续数据到达时触发 OE 溢出错误。
- **RX 字符超时中断**: Below-threshold 数据在 4 字符时间无新 RX 填充时触发 CTI (IIR=0xCC / 0x0C)；在 RBR 读取、FCR RCVR_RESET 或 FIFO 为空时清零。
- **VIC 中断映射**: `uart_16550_irq` 接入 SoC VIC 源 1 (`uart_tx_int`)。

### 明确排除的后续工作 (Future Work):
- Linux 8250 驱动完全无缝移植与系统级兼容
- 实板晶振/波特率容差与异步 Sampling CDC/RDC
- 完整 DMA 模式 (FCR[3] tie 0) 与全自动 CTS/RTS 平台流控闭合
- 形式验证 (Formal Proof)
- 覆盖率豁免文件 (Coverage Exclusion) 维护

---

## 1. 寄存器映射 (32-bit APB Bus, Byte Strobe Supported)

| Offset | 名称 (DLAB=0) | 名称 (DLAB=1) | RW | 说明 |
|:-:|---|---|:-:|---|
| 0x00 | RBR (读) / THR (写) | DLL | RW | 接收缓冲 / 发送保持；DLAB=1 时低 8 位除数 |
| 0x04 | IER | DLM | RW | 中断使能 (IER[3:0]) / 高 8 位除数 |
| 0x08 | IIR (读) / FCR (写) | -   | RW | 中断标识 / FIFO 控制 (FCR[2:1] 自清零) |
| 0x0C | LCR | -   | RW | Line control (DLAB, 帧格式) |
| 0x10 | MCR | -   | RW | Modem control (DTR, RTS, OUT1, OUT2, LOOP, AUTO_RTS) |
| 0x14 | LSR | -   | RO | Line status (读 LSR 清 OE) |
| 0x18 | MSR | -   | RO | Modem status (读 MSR 清 delta bits) |
| 0x1C | SCR | -   | RW | Scratchpad 寄存器 |

### 1.1 中断优先级与 IIR 编码

IIR (0x08 读) 编码与优先级如下 (IIR[7:6] 反映 `FCR[0]` FIFO_EN 状态)：

| 优先级 | 中断源 | IIR[3:0] (FIFO_EN=1) | IIR[3:0] (FIFO_EN=0) | 清零方式 |
|:-:|---|:-:|:-:|---|
| 1 (最高) | Receiver Line Status (LSI) | 0xC6 | 0x06 | 读 LSR 寄存器 |
| 2 | Received Data Available (RDA) | 0xC4 | 0x04 | 读 RBR 降至阈值以下 |
| 2 | Character Timeout Indication (CTI) | 0xCC | N/A  | 读 RBR 寄存器 / FIFO 清空 |
| 3 | Transmitter Holding Register Empty (THRE) | 0xC2 | 0x02 | 读 IIR 或是写 THR |
| 4 (最低) | Modem Status (MSR) | 0xC0 | 0x00 | 读 MSR 寄存器 |
| - | 无中断 pending | 0xC1 | 0x01 | - |

---

## 2. 验证门禁与基线命令

Phase 4E 自动化自测命令：

```bash
make dut-block-unit-gate
make uart-cpu-gate
make firmware
make uvm
RUN_DIR=build/soc_test/phase4e_uart_cpu FW_HEX=build/firmware/soc_smoke/firmware.hex tb/soc_test/run.sh
git diff --check
```

---

## 版本记录

- v2 (2026-07-27)：Phase 4E Commercial Hardening 闭合。补充 RX Timeout、IIR 8-bit width、FCR[2:1] 自清零、单字节兼容模式、MSR Delta 读清零及 VIC Source 1 映射与单元/固件门禁。
- v1 (2026-07-27)：更新为当前 DUT 基线；默认 FIFO 深度 16。
- v0 (2026-07-26)：初版规格草案。
