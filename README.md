# MIPS32 SoC Design & Verification Platform

这是一个完整、模块化且工程化度极高的 **32 位 MIPS32 嵌入式 SoC** 软核系统。项目集成了 MIPS32 处理器内核、五级流水线、CP0 协处理器、L1 Cache、AXI4/APB 混合总线拓扑、标准片内外设、JTAG 调试接口，以及基于 UVM 的芯片级验证自动化平台。

---

## 1. 架构总览 (Architecture Overview)

本 SoC 采用典型的 **CPU Core + AXI4/APB 双层总线 + 片上存储 + 丰富外设/调试接口** 的现代 SoC 架构设计：

```text
                        +---------------------------------------+
                        |               soc_top                 |
                        | (Board-level Pins: CLK, RST, GPIO...) |
                        +-------------------+-------------------+
                                            |
                        +-------------------+-------------------+
                                            |             mips_soc                  |
                        +-------------------+-------------------+
                                            |
        +-----------------------------------+-----------------------------------+
        |                                   |                                   |
+-------v-------+                   +-------v-------+                   +-------v-------+
| Core Subsys   |                   | JTAG Debug    |                   | DMA Master    |
| - MIPS32 CPU  |                   | Subsystem     |                   | Subsystem     |
| - I/D Cache   |                   +-------+-------+                   +-------+-------+
+-------+-------+                           |                                   |
        | (I-Code / D-Code)                 | (AXI Master)                      | (AXI Master)
        +-------------------+---------------+-----------------------------------+
                            |
                    +-------v-------+
                    |  soc_fabric   | <--- AXI4 Interconnect (Arbiter & Decoder)
                    +-------+-------+
                            |
        +-------------------+-------------------+-------------------+
        |                                       |                   |
+-------v-------+                       +-------v-------+   +-------v-------+
| Boot SRAM     |                       | SPI Flash     |   | AXI2APB Bridge|
| (64KB)        |                       | (XIP/Boot)    |   +-------+-------+
+---------------+                       +---------------+           |
                                                                    | (APB Bus)
                                    +-------------------------------+-------------------------------+
                                    |               |               |               |               |
                            +-------v-------+ +-----v-----+ +-------v-------+ +-----v-----+ +-------v-------+
                            |   APB UART    | | APB Timer | |   APB GPIO    | | APB DMA   | |   APB PIC     |
                            +---------------+ +-----------+ +---------------+ +-----------+ +-------+-------+
                                                                                                    | (IRQ)
                                                                                                    v
                                                                                            To CPU CP0 (Interrupt)
```

---

## 2. 核心子系统与关键特性

### 2.1 处理器内核 (Core Subsystem)
- **指令集 (ISA)**: 32位 MIPS32 标量处理器。
- **流水线**: 经典 **5 级流水线**（IF 取指 $\rightarrow$ ID 译码 $\rightarrow$ EX 执行 $\rightarrow$ MEM 访存 $\rightarrow$ WB 写回），具备完备的数据旁路转发 (Bypassing) 与冒险暂停逻辑。
- **CP0 协处理器**: 集成标准 MIPS32 CP0 寄存器，支持精确硬件中断响应、系统调用 (`Syscall`) 与异常处理返回 (`ERET`)。
- **乘除法单元 (MDU)**: 独立模块处理 `MULT`, `MULTU`, `DIV`, `DIVU` 及 `HI`/`LO` 寄存器读写。
- **L1 Cache**: 独立的指令缓存 (`icache.v`) 与数据缓存 (`dcache.v`)。

### 2.2 总线架构 (Fabric & Interconnect)
- **AXI4 主干总线**: 连接 CPU I-Cache、CPU D-Cache、DMA Master 及 JTAG Master，通过 `axi_arbiter_2x1` / `axi_decoder_1x3` 提供确定性仲裁与地址译码路由。
- **APB 桥接**: 通过 `axi2apb_bridge.v` 转换为低功耗 APB 总线挂载外设。

### 2.3 片内外设 (Peripherals)
- **PIC (可编程中断控制器)**: 聚合 UART、Timer、DMA 等外设中断源，进行屏蔽/优先级仲裁后统一上报 CPU CP0。
- **UART**: 串口控制器，支持 TX/RX IRQ 中断与控制台打印。
- **Timer**: 系统 Tick / 倒计时定时器。
- **GPIO**: 32 位通用输入输出，带方向控制及跨时钟域同步设计。
- **DMA**: AXI/APB DMA 控制器，支持 Memory-to-Memory 及 Memory-to-Peripheral 高速传输。
- **SPI Controller**: 驱动外部 SPI Flash。

### 2.4 调试与分层封装 (Debug & Partitioning)
- **JTAG TAP 控制器**: 支持标准 IEEE 1149.1 接口（TCK, TMS, TDI, TDO）。
- **产品与验证分离封装**:
  - `soc_top.v` / `mips_soc.v`: 产品级硬件顶层，仅暴露板级物理引脚。
  - `soc_verif_top.sv`: 验证层顶层，通过 SystemVerilog `bind` 绑定 `soc_observation_if` 观察点、故障注入器与仿真 SRAM/Flash 镜像加载。

---

## 3. 地址空间映射 (Address Map)

| 区域 (Region) | 基地址 (Base) | 大小 (Size) | 访问类型 | 用途说明 |
| :--- | :--- | :--- | :--- | :--- |
| **Boot SRAM** | `0x0000_0000` | 64 KB | Cacheable | 引导程序 / 复位向量入口 |
| **Boot SRAM Alias** | `0xA000_0000` | 64 KB | Uncached | Boot SRAM 非缓存别名（用于 DMA/Mailbox） |
| **SPI Flash** | `0x1000_0000` | 256 MB | Read-mostly | 固件镜像存储 / XIP 支持 |
| **APB 外设区** | `0x4000_0000` | 64 KB | Uncached | 包含 UART (`+0x0000`), Timer (`+0x1000`), GPIO (`+0x2000`), DMA (`+0x3000`), PIC (`+0x4000`) |

---

## 4. 工程规模与代码行数

| 代码分类 | 文件数 | 总行数 | 有效代码/注释行数 |
| :--- | :--- | :--- | :--- |
| **RTL 硬件设计** (`.v`, `.vh`) | 45 | 10,375 | 9,381 |
| **验证环境** (`.sv` / UVM) | 71 | 9,584 | 8,272 |
| **Firmware 固件** (`.c`, `.h`, `.asm`, `.s`, `.ld`) | 11 | 4,710 | 4,567 |
| **自动化脚本** (`.py`, `.sh`, `Makefile`) | 25 | 5,416 | 4,882 |
| **工程文档** (`.md`) | 12 | 1,699 | 1,502 |
| **核心源码小计** | **164** | **31,784** | **28,604** |

---

## 5. 目录结构 (Directory Layout)

```text
├── docs/               # 架构设计说明、地址映射与 Signoff 标准文档
├── rtl/                # RTL 硬件源代码
│   ├── cpu/            # MIPS32 CPU 内核、CP0、MDU 与 5 级流水线
│   ├── cache/          # I-Cache / D-Cache L1 缓存实现
│   ├── axi/            # AXI4 仲裁器、译码器与 AXI2APB 桥接器
│   ├── perips/         # APB 外设 (UART, Timer, GPIO, PIC, DMA, SPI, JTAG)
│   └── mips_soc.v      # SoC 系统集成顶层
├── tb/                 # 仿真与验证平台
│   └── uvm_tb/         # 基于 UVM 的芯片级验证环境
├── sim/                # 仿真运行目录与 Makefile 门限配置
└── Makefile            # 工程根目录编译与回归测试入口
```

---

## 6. 快速入门 (Quick Start)

### 环境初始化
在运行任何 EDA 工具（VCS/Verdi）前，需初始化 Module 环境：
```bash
source /etc/profile.d/modules.sh
module load vcs
```

### 常用运行命令
```bash
# 1. 编译固件产物
make firmware

# 2. 运行单项 UVM 烟雾测试
make uvm

# 3. 运行完整 UVM 回归测试
make uvm-regression

# 4. 编译固件并运行 UVM 回归测试
make regression

# 5. 执行 Phase 3 完整门限 Check
make phase3-complete
```
