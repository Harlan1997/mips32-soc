import os
import subprocess
import time

def run_regression(num_tests=20):
    print(f"Starting Regression Suite with {num_tests} Random Instruction Tests...")
    pass_count = 0
    fail_count = 0
    timeout_count = 0
    exception_count = 0
    
    # Pre-compile the RTL once
    print("Compiling RTL with VCS...")
    vcs_cmd = """
    source /etc/profile.d/modules.sh
    module load vcs
    vcs -full64 -sverilog -timescale=1ns/1ps -cm line+cond+fsm+branch+tgl +incdir+../../rtl/cpu \
    +incdir+../../rtl/axi +incdir+../../rtl/perips ../../rtl/cpu/mips_alu.v ../../rtl/cpu/mips_control.v \
    ../../rtl/cpu/mips_core.v ../../rtl/cpu/mips_cp0.v ../../rtl/cpu/mips_cpu.v ../../rtl/cpu/mips_ex_mem_reg.v \
    ../../rtl/cpu/mips_ex_stage.v ../../rtl/cpu/mips_id_ex_reg.v ../../rtl/cpu/mips_id_stage.v \
    ../../rtl/cpu/mips_if_id_reg.v ../../rtl/cpu/mips_if_stage.v ../../rtl/cpu/mips_mdu.v \
    ../../rtl/cpu/mips_mem_stage.v ../../rtl/cpu/mips_mem_wb_reg.v ../../rtl/cpu/mips_regfile.v \
    ../../rtl/cpu/mips_wb_stage.v ../../rtl/axi/axi2apb_bridge.v ../../rtl/axi/axi_arbiter_2x1_full.v \
    ../../rtl/axi/axi_arbiter_2x1.v ../../rtl/axi/axi_decoder_1x2.v ../../rtl/axi/axi_decoder_1x3.v \
    ../../rtl/perips/apb_axi_dma.v ../../rtl/perips/apb_gpio.v ../../rtl/perips/apb_pic.v \
    ../../rtl/perips/apb_timer.v ../../rtl/perips/apb_uart.v ../../rtl/perips/axi_spi_flash.v \
    ../../rtl/perips/axi_sram.v ../../rtl/perips/jtag_debug_top.v ../../rtl/cache/dcache.v \
    ../../rtl/cache/icache.v ../../rtl/mips_soc.v tb_mips_soc.v -l vcs_reg.log
    """
    subprocess.run(vcs_cmd, shell=True, executable="/bin/bash")
    
    for i in range(num_tests):
        print(f"--- Running Test {i+1}/{num_tests} ---")
        # 1. Generate random firmware
        subprocess.run(["python3", "gen_rand_mips.py"], cwd="fw")
        
        # 2. Compile firmware
        compile_cmd = """
        mips64-linux-gnu-gcc -mabi=32 -mips32 -EL -O2 -ffreestanding -nostdlib -G 0 -mno-abicalls -fno-pic -T link.ld -nostdlib rand_test.s -o firmware.elf
        mips64-linux-gnu-objcopy -O binary firmware.elf firmware.bin
        python3 elf2hex.py firmware.bin firmware.hex
        cp firmware.hex ../firmware.hex
        """
        subprocess.run(compile_cmd, shell=True, cwd="fw")
        
        # 3. Run simulation
        start_time = time.time()
        sim_cmd = f"source /etc/profile.d/modules.sh && module load vcs && ./simv -cm line+cond+fsm+branch+tgl -cm_name test_{i}"
        result = subprocess.run(sim_cmd, shell=True, executable="/bin/bash", stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        out = result.stdout
        
        # 4. Analyze results
        if "REGRESSION_TEST_SUCCESS" in out:
            print("Status: PASS (Mailbox success hit)")
            pass_count += 1
        elif "REGRESSION_TEST_FAILED" in out:
            print("Status: FAIL (Mailbox fail hit)")
            fail_count += 1
        elif "SoC Simulation Timeout" in out:
            print("Status: TIMEOUT (Stuck or infinite loop)")
            timeout_count += 1
        else:
            print("Status: UNKNOWN")
            fail_count += 1
            
        if "EXCEPTION TAKEN!" in out:
            exception_count += 1
            print("  Note: Hit an exception (e.g. Reserved Instruction) but pipeline survived.")
            
    print("\n=============================================")
    print("      REGRESSION SUITE SUMMARY")
    print("=============================================")
    print(f"Total Tests Run   : {num_tests}")
    print(f"Passed            : {pass_count}")
    print(f"Failed            : {fail_count}")
    print(f"Timed Out         : {timeout_count}")
    print(f"Tests with Except : {exception_count}")
    print("=============================================\n")
    
    # Generate accumulated coverage report
    print("Generating accumulated coverage report...")
    urg_cmd = "source /etc/profile.d/modules.sh && module load vcs && urg -dir simv.vdb -report textReportFinal -format text"
    subprocess.run(urg_cmd, shell=True, executable="/bin/bash")

if __name__ == "__main__":
    run_regression(50)
