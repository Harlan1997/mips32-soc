#!/usr/bin/env python3
"""Check the Linux DT/config inputs for the SoC peripheral contract."""
from pathlib import Path
import re
import sys


def fail(message: str) -> None:
    print(f"LINUX_SOC_CONTRACT_AUDIT_FAIL: {message}")
    raise SystemExit(1)


root = Path(__file__).resolve().parents[1]
dts_paths = [
    root / "tb/linux_boot/mips32_soc_ref.dts",
    root / "tb/linux_boot/mips32_soc_ref_rtl.dts",
]
for dts_path in dts_paths:
    dts = dts_path.read_text(encoding="utf-8")
    required = {
        'compatible = "harlan,mips32-soc-ref";': "machine compatible",
        'compatible = "harlan,mips32-soc-vic";': "VIC compatible",
        'compatible = "wd,mbl-gpio";': "GPIO compatible",
        'reg-names = "dat", "dirout";': "GPIO data/direction registers",
        "gpio-controller;": "GPIO controller marker",
        "#gpio-cells = <2>;": "GPIO cell format",
    }
    for needle, label in required.items():
        if needle not in dts:
            fail(f"{dts_path}: missing {label}")
    if not re.search(
        r"gpio@40002000\s*\{[^}]*reg\s*=\s*<0x40002000\s+0x4>\s*,\s*<0x40002004\s+0x4>",
        dts,
        re.S,
    ):
        fail(f"{dts_path}: GPIO register map is not 0x40002000/0x40002004")

config_path = Path(sys.argv[1]) if len(sys.argv) == 2 else None
if config_path is not None:
    config = config_path.read_text(encoding="utf-8")
    for symbol in ("CONFIG_GPIOLIB", "CONFIG_GPIO_GENERIC_PLATFORM"):
        if not re.search(rf"^{re.escape(symbol)}=(?:y|m)$", config, re.M):
            fail(f"{config_path}: {symbol} is not enabled")

print(f"LINUX_SOC_CONTRACT_AUDIT_PASS dts={len(dts_paths)} gpio=32")
