# DDR4 外部输入获取指南

> 版本：v0.2（2026-08-02）
> 适用目标：ASIC Profile C1，TSMC N28/28HPC RFQ target，DDR4-2133，x32
> single-rank，BGA，1.2 V commercial。

这些资料不在 TSMC PDK 中，需要由 PHY vendor、DRAM vendor、package/OSAT、
板卡团队和 SI/PI 工程团队分别提供。所有资料只登记路径、版本、SHA256、
license owner 和 review 状态，不复制到 Git。

## 0. 当前 RTL 前端范围

当前项目暂不进入综合阶段，只要求 RTL 功能编写、前端编译/elaboration 和功能仿真。
因此以下输入现在不是阻塞条件：

- TSMC N28/N28HPC PDK 和 DDR IO library；
- Synopsys 真实 PHY license、DFI port list 和 implementation model；
- 精确 DRAM ordering code；
- package ball map/parasitic 和 PCB SI/PI/timing 文件。

当前允许使用 vendor-neutral contract、代表性 timing 参数和 behavioral PHY/DRAM model，
完成初始化、training、refresh、读写、背压、reset 和错误路径仿真。该结果只能标为
`RTL_FUNCTIONAL_SIM_READY` 或 `BLOCK_VERIFIED (vendor-neutral)`，不能把
`DDR4_ENTRY_READY` 改为 `1`。

本清单的 `DDR4-IN-01..08` 是后续真实 PHY/controller 和 ASIC 产品入口的验收项，
不是当前 RTL 前端 gate 的前置条件。

## 1. 获取顺序

### 1.1 先向 PHY vendor 索取 supported-part list

向 Synopsys（当前 RFQ 优先对象）索取：

- 支持的 TSMC N28/28HPC 具体 PDK/IO release；
- DDR4-2133/2400、x32、single-rank 支持矩阵；
- 推荐 DRAM vendor、ordering code、rank/width/density；
- PHY reference board、package/ball map 和推荐 ODT/drive strength；
- vendor 要求的 board stackup、trace impedance、CK/DQS skew 和 length budget。

PHY 支持列表是 DRAM 选型的约束，不能先购买一个未经 PHY 确认的颗粒。

### 1.2 从 DRAM vendor 获取颗粒资料

根据 PHY 支持列表向 Micron、Samsung 或 SK hynix 索取精确 ordering code
的资料。公开 datasheet 可先用于筛选，正式产品应取得 vendor/NDA 版本：

- datasheet 和 speed-bin revision；
- AC/DC timing：tCK、tRCD、tRP、tRAS、tRFC、tREFI、CL/CWL、写 leveling；
- VDD/VDDQ/VPP、温度等级、ODT/Rtt、drive strength；
- x8/x16 组织、rank/density、地址/Bank/Bank-group 组织；
- IBIS/IBIS-AMI、Verilog/SystemVerilog memory model 和 license；
- errata、supported package、替代料和生命周期状态。

首版应锁定一个主料和一个兼容替代料；替代料必须重新跑 timing/SI/PI，不能
仅凭 pin-compatible 声明合并。

### 1.3 从 package/OSAT 获取封装资料

向封装供应商或 OSAT 索取与 BGA 目标一致的 package design kit：

- package drawing、ball map、bump/ball assignment；
- package substrate stackup、trace length/width/spacing；
- package parasitic、IBIS 或 S-parameter/Touchstone 模型；
- DDR IO 电源/地球分布、回流路径、decap 和热/温度约束；
- package escape/length-matching 规则以及与 PHY IO placement 的限制。

没有 ball map、stackup 和 parasitic，板级 SI/PI 结果只能算早期估算。

### 1.4 从板卡团队获取 SI/PI/timing 文件

板卡团队或 SI/PI 服务商应基于 PHY 推荐值和 package 数据输出：

- PCB stackup、材料、阻抗和 via/escape 规则；
- DDR4 net class：CK/CA/DQ/DQS/DM/ODT/RESET/ZQ；
- 每条 net 的 min/max length、组内 skew、CK-to-DQS budget；
- 拓扑、DRAM placement、termination、ODT/drive strength 配置；
- IBIS/S-parameter 输入清单和 corner（电压、温度、process、封装）；
- eye diagram、crosstalk、SSN、power droop、timing margin 报告；
- HyperLynx、Sigrity、ADS 或等效工具的工程文件和版本。

板级报告必须能追溯到具体 DRAM ordering code、package revision 和 PHY
配置；只给一张“DDR4 可用”的截图不能关闭 `DDR4-IN-06`。

## 2. 责任和交付物

| 输入 | 主要来源 | 责任 owner | 对应清单 |
|---|---|---|---|
| DRAM part/timing/model | DRAM vendor + PHY vendor | board/hardware + verification | `DDR4-IN-05`, `DDR4-IN-07` |
| package/ball/stackup | package/OSAT + PHY vendor | package/board | `DDR4-IN-02`, `DDR4-IN-06` |
| SI/PI/timing/ODT | board/SI/PI team | board/implementation | `DDR4-IN-06` |
| PHY supported list/DFI | Synopsys + foundry | memory/implementation | `DDR4-IN-03`, `DDR4-IN-04` |
| PLL/reset/WDT budget | SoC clock/system + PHY vendor | clock/system | `DDR4-IN-08` |

## 3. 无板卡或无 NDA 时的临时资料

- DRAM vendor 公共 datasheet：只能用于参数预筛选；不能关闭产品输入；
- PHY vendor reference board：可用于 F1/F2 prototype，不能替代目标 package/PCB；
- 公开 Micron memory model：可用于 controller unit test，不能替代真实 PHY；
- package/board 假设值：只能标为 `PROVISIONAL`，不能把 `DDR4_ENTRY_READY`
  改为 `1`。

## 4. 建议的索取邮件内容

请求中应明确写出：

```text
Target: TSMC N28/28HPC, BGA, DDR4-2133, x32 single-rank, 1.2 V,
commercial 0..85 C.
Please provide the supported DRAM ordering codes, package/ball map,
SI/PI stackup and timing constraints, ODT/drive-strength settings,
IBIS/Verilog models, DFI port list/ratio, training semantics, and all
license/redistribution restrictions.
```

收到资料后先建立 `path | version | SHA256 | license | owner | review date`
登记，再更新 [`docs/ddr4_integration_inputs.md`](ddr4_integration_inputs.md)。
