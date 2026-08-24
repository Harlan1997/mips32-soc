import os
import shlex
import subprocess
import time
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parents[1]
FW_SRC_DIR = SCRIPT_DIR / "fw"


def run_bash(command, cwd, capture=False):
    return subprocess.run(
        command,
        shell=True,
        executable="/bin/bash",
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        check=False,
    )


def vcs_file_list():
    files = [
        "rtl/cpu/mips_alu.v",
        "rtl/cpu/mips_control.v",
        "rtl/cpu/mips_core.v",
        "rtl/cpu/mips_cp0.v",
        "rtl/cpu/mips_tlb.v",
        "rtl/cpu/mips_micro_tlb.v",
        "rtl/cpu/mips_mmu.v",
        "rtl/cpu/mips_bpu.v",
        "rtl/cpu/mips_cpu.v",
        "rtl/cpu/mips_ex_mem_reg.v",
        "rtl/cpu/mips_ex_stage.v",
        "rtl/cpu/mips_id_ex_reg.v",
        "rtl/cpu/mips_id_stage.v",
        "rtl/cpu/mips_if_id_reg.v",
        "rtl/cpu/mips_if_stage.v",
        "rtl/cpu/mips_mdu.v",
        "rtl/cpu/mips_mem_stage.v",
        "rtl/cpu/mips_mem_wb_reg.v",
        "rtl/cpu/mips_regfile.v",
        "rtl/cpu/mips_wb_stage.v",
        "rtl/axi/axi2apb_bridge.v",
        "rtl/axi/axi_arbiter_2x1_full.v",
        "rtl/axi/axi_arbiter_2x1.v",
        "rtl/axi/axi_decoder_1x3.v",
        "rtl/perips/apb_axi_dma.v",
        "rtl/perips/apb_gpio.v",
        "rtl/perips/apb_pic.v",
        "rtl/perips/apb_timer.v",
        "rtl/perips/apb_uart.v",
        "rtl/perips/apb_qspi_status.v",
        "rtl/perips/qspi_cmd_behavioral.v",
        "rtl/perips/qspi_apb_integration.v",
        "rtl/perips/qspi_shared_pin_arbiter.v",
        "rtl/perips/qspi_soc_pad_mux.v",
        "rtl/perips/qspi_axi_xip.v",
        "rtl/perips/axi_spi_flash.v",
        "rtl/perips/axi_flash_image_model.v",
        "rtl/perips/axi_sram.v",
        "rtl/perips/axi_ddr_model.v",
        "rtl/perips/jtag_debug_top.v",
        "rtl/cache/dcache.v",
        "rtl/cache/icache.v",
        "rtl/soc_fabric.v",
        "rtl/soc_core_subsystem.v",
        "rtl/soc_memory_subsystem.v",
        "rtl/soc_peripheral_subsystem.v",
        "rtl/soc_debug_subsystem.v",
        "rtl/mips_soc_impl.v",
        "rtl/mips_soc.v",
        "rtl/soc_top.v",
    ]
    return " ".join(shlex.quote(str(ROOT_DIR / path)) for path in files)


def compile_random_firmware(fw_run_dir):
    cross = os.environ.get("CROSS_COMPILE", "mips64-linux-gnu-")
    cc = os.environ.get("CC", f"{cross}gcc")
    objcopy = os.environ.get("OBJCOPY", f"{cross}objcopy")
    linker = FW_SRC_DIR / "link.ld"
    elf2hex = FW_SRC_DIR / "elf2hex.py"

    subprocess.run(
        ["python3", str(FW_SRC_DIR / "gen_rand_mips.py")],
        cwd=fw_run_dir,
        check=True,
    )

    compile_cmd = f"""
    {shlex.quote(cc)} -mabi=32 -mips32 -EL -O2 -ffreestanding -nostdlib -G 0 -mno-abicalls -fno-pic \
        -T {shlex.quote(str(linker))} -nostdlib rand_test.s -o firmware.elf
    {shlex.quote(objcopy)} -O binary firmware.elf firmware.bin
    python3 {shlex.quote(str(elf2hex))} firmware.bin firmware.hex
    """
    result = run_bash(compile_cmd, fw_run_dir, capture=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr or result.stdout)

    return fw_run_dir / "firmware.hex"


def run_regression(num_tests=20):
    run_dir = Path(os.environ.get("RUN_DIR", ROOT_DIR / "build/soc_test/random_regression")).resolve()
    firmware_dir = run_dir / "firmware"
    logs_dir = run_dir / "logs"
    firmware_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)

    print(f"Run directory: {run_dir}")
    print(f"Starting Regression Suite with {num_tests} Random Instruction Tests...")
    pass_count = 0
    fail_count = 0
    timeout_count = 0
    exception_count = 0

    print("Compiling RTL with VCS...")
    vcs_cmd = f"""
    source /etc/profile.d/modules.sh
    if [ -d /tool/module ]; then module use /tool/module; fi
    module load vcs
    vcs -full64 -sverilog -timescale=1ns/1ps -cm line+cond+fsm+branch+tgl \
        +incdir+{shlex.quote(str(ROOT_DIR / "rtl/include"))} \
        +incdir+{shlex.quote(str(ROOT_DIR / "rtl/cpu"))} \
        +incdir+{shlex.quote(str(ROOT_DIR / "rtl/axi"))} \
        +incdir+{shlex.quote(str(ROOT_DIR / "rtl/perips"))} \
        +incdir+{shlex.quote(str(SCRIPT_DIR))} \
        {vcs_file_list()} {shlex.quote(str(SCRIPT_DIR / "tb_mips_soc.v"))} -l vcs_reg.log
    """
    result = run_bash(vcs_cmd, run_dir, capture=False)
    if result.returncode != 0:
        raise SystemExit(result.returncode)

    for i in range(num_tests):
        test_idx = i + 1
        print(f"--- Running Test {test_idx}/{num_tests} ---")
        fw_run_dir = firmware_dir / f"test_{test_idx:03d}"
        fw_run_dir.mkdir(parents=True, exist_ok=True)

        try:
            fw_hex = compile_random_firmware(fw_run_dir)
        except RuntimeError as exc:
            print(f"Status: FAIL (firmware build failed: {exc})")
            fail_count += 1
            continue

        start_time = time.time()
        sim_cmd = f"""
        source /etc/profile.d/modules.sh
        if [ -d /tool/module ]; then module use /tool/module; fi
        module load vcs
        ./simv +FW_HEX={shlex.quote(str(fw_hex))} -cm line+cond+fsm+branch+tgl -cm_name test_{test_idx}
        """
        result = run_bash(sim_cmd, run_dir, capture=True)
        out = (result.stdout or "") + (result.stderr or "")
        (logs_dir / f"test_{test_idx:03d}.log").write_text(out)

        if "REGRESSION_TEST_SUCCESS" in out:
            print(f"Status: PASS ({time.time() - start_time:.1f}s)")
            pass_count += 1
        elif "REGRESSION_TEST_FAILED" in out:
            print("Status: FAIL (Mailbox fail hit)")
            fail_count += 1
        elif "SoC Simulation Timeout" in out:
            print("Status: TIMEOUT (Stuck or infinite loop)")
            timeout_count += 1
        else:
            print(f"Status: UNKNOWN (sim status {result.returncode})")
            fail_count += 1

        if "EXCEPTION TAKEN!" in out:
            exception_count += 1
            print("  Note: Hit an exception but pipeline survived.")

    summary = f"""
=============================================
      REGRESSION SUITE SUMMARY
=============================================
Total Tests Run   : {num_tests}
Passed            : {pass_count}
Failed            : {fail_count}
Timed Out         : {timeout_count}
Tests with Except : {exception_count}
=============================================
"""
    print(summary)
    (run_dir / "regression_summary.txt").write_text(summary)

    print("Generating accumulated coverage report...")
    urg_cmd = """
    source /etc/profile.d/modules.sh
    if [ -d /tool/module ]; then module use /tool/module; fi
    module load vcs
    urg -dir simv.vdb -report textReportFinal -format text
    """
    result = run_bash(urg_cmd, run_dir, capture=False)
    if result.returncode != 0:
        raise SystemExit(result.returncode)


if __name__ == "__main__":
    run_regression(int(os.environ.get("NUM_TESTS", "50")))
