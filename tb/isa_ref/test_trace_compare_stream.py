#!/usr/bin/env python3
"""Mutation tests for the full streaming architectural comparator."""

import json
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading


COMPARATOR = Path(__file__).with_name("trace_compare.py")
TRACE_VALIDATOR = Path(__file__).parents[2] / "scripts" / "validate_linux_differential.py"
CONVERTER_PATH = Path(__file__).with_name("qemu_system_state_to_jsonl.py")
CONVERTER_SPEC = importlib.util.spec_from_file_location(
    "qemu_system_state_to_jsonl", CONVERTER_PATH)
CONVERTER = importlib.util.module_from_spec(CONVERTER_SPEC)
assert CONVERTER_SPEC.loader is not None
CONVERTER_SPEC.loader.exec_module(CONVERTER)


def record(seq, pc, instr, gpr_data):
    return {
        "retire_seq": seq,
        "schema": "00010000",
        "pc": pc,
        "instr": instr,
        "next_pc": f"{int(pc, 16) + 4:08x}",
        "gpr_we": 1,
        "gpr_addr": 2,
        "gpr_data": gpr_data,
        "cp0_we": 0,
        "cp0_addr": 0,
        "cp0_sel": 0,
        "cp0_data": "00000000",
        "fpr_state": "0",
        "fcsr_state": "00000000",
        "mem_valid": 0,
        "mem_read": 0,
        "mem_write": 0,
        "mem_addr": "00000000",
        "mem_wdata": "00000000",
        "mem_wdata_hi": "00000000",
        "mem_be": "f",
        "mem_rdata": "00000000",
        "except": 0,
        "except_code": 0,
        "bd": 0,
        "eret": 0,
    }


def write_trace(path, records):
    path.write_text("".join(json.dumps(item) + "\n" for item in records),
                    encoding="ascii")


def compare(root, rtl_records, qemu_records, stream=True):
    rtl_path = root / "rtl.jsonl"
    qemu_path = root / "qemu.jsonl"
    write_trace(rtl_path, rtl_records)
    write_trace(qemu_path, qemu_records)
    command = [sys.executable, str(COMPARATOR)]
    if stream:
        command.append("--stream")
    command.extend((str(rtl_path), str(qemu_path)))
    return subprocess.run(
        command,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        check=False)


def compare_fifos(root, rtl_records, qemu_records):
    rtl_path = root / "rtl.fifo"
    qemu_path = root / "qemu.fifo"
    os.mkfifo(rtl_path)
    os.mkfifo(qemu_path)
    command = [sys.executable, str(COMPARATOR), "--stream",
               str(rtl_path), str(qemu_path)]
    process = subprocess.Popen(
        command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    writer_error = []

    def write_streams():
        try:
            for path, records in ((rtl_path, rtl_records),
                                  (qemu_path, qemu_records)):
                with path.open("w", encoding="ascii") as stream:
                    stream.write("".join(
                        json.dumps(item) + "\n" for item in records))
        except BaseException as exc:
            writer_error.append(exc)

    writer = threading.Thread(target=write_streams, daemon=True)
    writer.start()
    stdout, _ = process.communicate(timeout=30)
    writer.join(timeout=1)
    if writer.is_alive():
        raise AssertionError(
            f"FIFO writer did not complete; comparator status="
            f"{process.returncode}; output={stdout!r}")
    if writer_error:
        raise AssertionError(f"FIFO writer failed: {writer_error[0]}")
    return subprocess.CompletedProcess(command, process.returncode, stdout)


def register_state(pc, **updates):
    registers = {f"r{index}": "00000000" for index in range(32)}
    registers.update({f"fpr{index}": "00000000" for index in range(32)})
    registers.update({"cause": "00000000", "epc": "00000000",
                      "index": "00000000", "pagemask": "00000000",
                      "entryhi": "00000000", "status": "00000000",
                      "hi": "00000000", "lo": "00000000",
                      "fcsr": "00000000"})
    registers.update(updates)
    return {"pc": pc, "regs": registers}


def schema_v2(item, hilo_state="0000000000000000"):
    result = dict(item)
    result.update({"schema": "00020000", "gpr_state": "0" * 256,
                   "hilo_state": hilo_state})
    return result


def with_gpr_word(item, address, value):
    result = dict(item)
    state = result["gpr_state"]
    offset = (31 - address) * 8
    result["gpr_state"] = state[:offset] + value + state[offset + 8:]
    return result


def main():
    count_read = record(0, "88010330", "40024800", "0402001d")
    arithmetic = record(1, "88010334", "24420001", "0402001e")

    with tempfile.TemporaryDirectory(prefix="trace-compare-stream-") as name:
        root = Path(name)
        result = compare(root, [count_read, arithmetic],
                         [count_read, arithmetic])
        assert result.returncode == 0, result.stdout
        assert "TRACE_COMPARE_PASS records=2 mode=stream" in result.stdout
        result = compare_fifos(root, [count_read, arithmetic],
                               [count_read, arithmetic])
        assert result.returncode == 0, result.stdout
        assert "TRACE_COMPARE_PASS records=2 mode=stream" in result.stdout

        sync_fault = record(0, "00400374", "02231821", "00000000")
        sync_fault.update({"gpr_we": 0, "gpr_addr": 0, "except": 1,
                           "except_code": 2, "next_pc": "88e08000"})
        sync_handler = record(1, "88e08000", "401b2000", "00002000")
        sync_handler["gpr_addr"] = 27
        sync_handler.update({"qemu_cause": "00000008",
                             "qemu_epc": "00400374"})
        sync_handler_next = record(2, "88e08004", "3c1a88d7", "88d70000")
        sync_handler_next["gpr_addr"] = 26
        rtl_sync_fault = [sync_fault, sync_handler, sync_handler_next]
        qemu_sync_fault = [dict(sync_handler, retire_seq=0),
                           dict(sync_handler_next, retire_seq=1)]
        result = compare(root, rtl_sync_fault, qemu_sync_fault)
        assert result.returncode == 0, result.stdout
        assert "TRACE_COMPARE_PASS records=2 mode=stream " \
               "rtl_consumed=3 golden_consumed=2 " \
               "rtl_unpaired=1 golden_unpaired=0" in result.stdout
        assert "TRACE_COMPARE_UNPAIRED_SUMMARY side=rtl total=1 " \
               "reasons=rtl_sync_exception_redirect:1" in result.stdout
        assert '"reason":"rtl_sync_exception_redirect"' in result.stdout
        assert '"pc":"00400374"' in result.stdout
        assert "TRACE_COMPARE_SYNC_EXCEPTION_PASS count=1" in result.stdout
        assert '"qemu_epc":"00400374"' in result.stdout
        result = compare(root, rtl_sync_fault, qemu_sync_fault, stream=False)
        assert result.returncode == 0, result.stdout

        wrong_sync_cause = dict(sync_handler, qemu_cause="0000000c")
        result = compare(root, rtl_sync_fault,
                         [wrong_sync_cause, sync_handler_next])
        assert result.returncode == 2, result.stdout
        assert "except_code:QEMU=00000003/RTL=00000002" in result.stdout

        wrong_sync_epc = dict(sync_handler, qemu_epc="00400370")
        result = compare(root, rtl_sync_fault,
                         [wrong_sync_epc, sync_handler_next])
        assert result.returncode == 2, result.stdout
        assert "epc:QEMU=00400370/RTL=00400374" in result.stdout

        wrong_sync_redirect = dict(sync_fault, next_pc="88e08180")
        result = compare(root, [wrong_sync_redirect, sync_handler,
                                sync_handler_next], qemu_sync_fault)
        assert result.returncode == 1, result.stdout
        assert "field=pc" in result.stdout, result.stdout

        irq_boundary = record(0, "88571e00", "10400005", "00000000")
        irq_boundary.update({"gpr_we": 0, "gpr_addr": 0,
                             "next_pc": "88e08200", "except": 1,
                             "except_code": 0})
        irq_vector = record(0, "88e08200", "0a0008e8", "00000000")
        irq_handler = record(1, "88e08204", "00000000", "00000000")
        rtl_irq = [irq_vector, irq_handler]
        qemu_irq = [irq_boundary,
                    dict(irq_vector, retire_seq=1),
                    dict(irq_handler, retire_seq=2)]
        result = compare(root, rtl_irq, qemu_irq)
        assert result.returncode == 0, result.stdout
        assert "TRACE_COMPARE_PASS records=2 mode=stream" in result.stdout
        assert "TRACE_COMPARE_UNPAIRED_SUMMARY side=golden total=1 " \
               "reasons=golden_async_interrupt_boundary:1" in result.stdout
        result = compare(root, rtl_irq, qemu_irq, stream=False)
        assert result.returncode == 0, result.stdout

        irq_handoff_prefix = record(0, "88a43b90", "00882021", "895d0400")
        irq_handoff_jr = record(1, "88a43b94", "01200008", "00000000")
        irq_handoff_jr.update({"gpr_we": 0, "gpr_addr": 0})
        irq_handoff_boundary = record(2, "88a43b98", "00000000", "00000000")
        irq_handoff_boundary.update({"gpr_we": 0, "gpr_addr": 0,
                                     "except": 1, "except_code": 0,
                                     "next_pc": "88e08200"})
        rtl_irq_handoff = [irq_handoff_prefix,
                           dict(irq_vector, retire_seq=1),
                           dict(irq_handler, retire_seq=2)]
        qemu_irq_handoff = [irq_handoff_prefix, irq_handoff_jr,
                            irq_handoff_boundary,
                            dict(irq_vector, retire_seq=3),
                            dict(irq_handler, retire_seq=4)]
        result = compare(root, rtl_irq_handoff, qemu_irq_handoff)
        assert result.returncode == 0, result.stdout
        assert "TRACE_COMPARE_PASS records=3 mode=stream " \
               "rtl_consumed=3 golden_consumed=5 " \
               "rtl_unpaired=0 golden_unpaired=2" in result.stdout
        result = compare(root, rtl_irq_handoff, qemu_irq_handoff,
                         stream=False)
        assert result.returncode == 0, result.stdout

        side_effecting_jr = dict(irq_handoff_jr, gpr_we=1, gpr_addr=31,
                                 gpr_data="88a43b98")
        result = compare(root, rtl_irq_handoff,
                         [irq_handoff_prefix, side_effecting_jr,
                          irq_handoff_boundary,
                          dict(irq_vector, retire_seq=3),
                          dict(irq_handler, retire_seq=4)])
        assert result.returncode == 1, result.stdout
        assert "field=pc" in result.stdout, result.stdout

        mutated_count = dict(count_read, gpr_data="0402001e")
        result = compare(root, [count_read, arithmetic],
                         [mutated_count, arithmetic])
        assert result.returncode == 1, result.stdout
        assert "field=gpr_data" in result.stdout, result.stdout

        index_miss_rtl = record(0, "880292dc", "40130000", "80000000")
        index_miss_rtl["gpr_addr"] = 19
        index_miss_qemu = dict(index_miss_rtl, gpr_data="8000001a")
        for stream in (True, False):
            result = compare(root, [index_miss_rtl], [index_miss_qemu],
                             stream=stream)
            assert result.returncode == 0, result.stdout

            # The P bit itself remains architecturally significant.
            index_hit_qemu = dict(index_miss_qemu, gpr_data="0000001a")
            result = compare(root, [index_miss_rtl], [index_hit_qemu],
                             stream=stream)
            assert result.returncode == 1, result.stdout
            assert "field=gpr_data" in result.stdout, result.stdout

            # The same data difference remains strict for non-Index reads.
            ordinary_read = dict(index_miss_rtl, instr="00000000")
            ordinary_read_qemu = dict(ordinary_read,
                                     gpr_data="8000001a")
            result = compare(root, [ordinary_read], [ordinary_read_qemu],
                             stream=stream)
            assert result.returncode == 1, result.stdout
            assert "field=gpr_data" in result.stdout, result.stdout

        index_hit_rtl = dict(index_miss_rtl, gpr_data="00000000")
        index_hit_qemu = dict(index_hit_rtl, gpr_data="0000001a")
        result = compare(root, [index_hit_rtl], [index_hit_qemu])
        assert result.returncode == 1, result.stdout
        assert "field=gpr_data" in result.stdout, result.stdout

        index_miss_rtl_v2 = with_gpr_word(
            schema_v2(index_miss_rtl), 19, "80000000")
        index_miss_qemu_v2 = with_gpr_word(
            dict(index_miss_rtl_v2, gpr_data="8000001a"), 19, "8000001a")
        for stream in (True, False):
            result = compare(root, [index_miss_rtl_v2],
                             [index_miss_qemu_v2], stream=stream)
            assert result.returncode == 0, result.stdout

            # The Index exception is limited to the destination register.
            other_register_diff = with_gpr_word(
                index_miss_qemu_v2, 18, "00000001")
            result = compare(root, [index_miss_rtl_v2],
                             [other_register_diff], stream=stream)
            assert result.returncode == 1, result.stdout
            assert "field=gpr_state" in result.stdout, result.stdout

            # The Index miss bit remains significant in schema-v2 state.
            index_hit_qemu_v2 = with_gpr_word(
                dict(index_miss_qemu_v2, gpr_data="0000001a"),
                19, "0000001a")
            result = compare(root, [index_miss_rtl_v2],
                             [index_hit_qemu_v2], stream=stream)
            assert result.returncode == 1, result.stdout
            assert "field=gpr_data" in result.stdout, result.stdout

            index_miss_next_rtl = record(
                1, "880292e0", "24420001", "00000001")
            index_miss_next_rtl = with_gpr_word(
                schema_v2(index_miss_next_rtl), 19, "80000000")
            index_miss_next_rtl = with_gpr_word(
                index_miss_next_rtl, 2, "00000001")
            index_miss_next_qemu = with_gpr_word(
                dict(index_miss_next_rtl), 19, "8000001a")
            result = compare(
                root, [index_miss_rtl_v2, index_miss_next_rtl],
                [index_miss_qemu_v2, index_miss_next_qemu], stream=stream)
            assert result.returncode == 0, result.stdout

            # Only the tainted destination's Index low bits are ignored.
            persistent_other_register_diff = with_gpr_word(
                index_miss_next_qemu, 18, "00000001")
            result = compare(
                root, [index_miss_rtl_v2, index_miss_next_rtl],
                [index_miss_qemu_v2, persistent_other_register_diff],
                stream=stream)
            assert result.returncode == 1, result.stdout
            assert "field=gpr_state" in result.stdout, result.stdout

            index_overwrite_rtl = dict(
                index_miss_next_rtl, retire_seq=2, pc="880292e4",
                instr="26730001", next_pc="880292e8", gpr_addr=19,
                gpr_data="12345678")
            index_overwrite_rtl = with_gpr_word(
                index_overwrite_rtl, 19, "12345678")
            index_overwrite_qemu = with_gpr_word(
                dict(index_overwrite_rtl), 19, "12345679")
            result = compare(
                root,
                [index_miss_rtl_v2, index_miss_next_rtl,
                 index_overwrite_rtl],
                [index_miss_qemu_v2, index_miss_next_qemu,
                 index_overwrite_qemu], stream=stream)
            assert result.returncode == 1, result.stdout
            assert "field=gpr_state" in result.stdout, result.stdout

        rtl_eret = record(0, "88e08058", "42000018", "00000000")
        rtl_eret.update({"gpr_we": 0, "gpr_addr": 0,
                         "next_pc": "0040039c", "eret": 1})
        qemu_eret = dict(rtl_eret, **{"except": 1, "except_code": 2})
        rtl_fetch_fault = record(1, "0040039c", "00031840", "00000000")
        rtl_fetch_fault.update({"gpr_we": 0, "gpr_addr": 0,
                                "except": 1, "except_code": 2,
                                "next_pc": "88e08180"})
        qemu_handler = record(1, "88e08180", "401b2000", "00002000")
        qemu_handler["gpr_addr"] = 27
        qemu_handler.update({"qemu_cause": "00000008",
                             "qemu_epc": "0040039c"})
        rtl_handler = dict(qemu_handler, retire_seq=2)
        result = compare(root, [rtl_eret, rtl_fetch_fault, rtl_handler],
                         [qemu_eret, qemu_handler])
        assert result.returncode == 0, result.stdout
        assert "TRACE_COMPARE_PASS records=2 mode=stream " \
               "rtl_consumed=3 golden_consumed=2 " \
               "rtl_unpaired=1 golden_unpaired=0" in result.stdout
        result = compare(root, [rtl_eret, rtl_fetch_fault, rtl_handler],
                         [qemu_eret, qemu_handler], stream=False)
        assert result.returncode == 0, result.stdout
        assert "TRACE_COMPARE_PASS records=2" in result.stdout

        wrong_fetch_code = dict(rtl_fetch_fault, except_code=3)
        result = compare(root, [rtl_eret, wrong_fetch_code, rtl_handler],
                         [qemu_eret, qemu_handler])
        assert result.returncode == 1, result.stdout
        assert "field=except" in result.stdout, result.stdout
        result = compare(root, [rtl_eret, wrong_fetch_code, rtl_handler],
                         [qemu_eret, qemu_handler], stream=False)
        assert result.returncode == 1, result.stdout
        assert "except" in result.stdout, result.stdout

        calibration = record(0, "8800fe54", "24420001", "00000001")
        mutated_calibration = dict(calibration, gpr_data="00000002")
        result = compare(root, [calibration], [mutated_calibration])
        assert result.returncode == 1, result.stdout
        assert "field=gpr_data" in result.stdout, result.stdout

        cp0_write = dict(record(0, "88010330", "40825800", "00000000"),
                         gpr_we=0, gpr_addr=0, cp0_we=1, cp0_addr=11,
                         cp0_sel=0, cp0_data="0401b6af")
        mutated_cp0_write = dict(cp0_write, cp0_data="0401b6ae")
        result = compare(root, [cp0_write], [mutated_cp0_write])
        assert result.returncode == 1, result.stdout
        assert "field=cp0_data" in result.stdout, result.stdout

        alias_pairs = [
            (record(0, "80001000", "24420001", "00000001"),
             record(0, "a0001000", "24420001", "00000001"), "pc"),
            (dict(record(0, "80001000", "24420001", "00000001"),
                  next_pc="80001004"),
             dict(record(0, "80001000", "24420001", "00000001"),
                  next_pc="a0001004"), "next_pc"),
            (record(0, "80001000", "24420001", "80000000"),
             record(0, "80001000", "24420001", "a0000000"), "gpr_data"),
            (dict(cp0_write, cp0_data="80000000"),
             dict(cp0_write, cp0_data="a0000000"), "cp0_data"),
            (dict(record(0, "80001000", "8c420000", "00000001"),
                  mem_valid=1, mem_read=1, mem_addr="80002000"),
             dict(record(0, "80001000", "8c420000", "00000001"),
                  mem_valid=1, mem_read=1, mem_addr="a0002000"), "mem_addr"),
        ]
        for rtl_record, qemu_record, field in alias_pairs:
            result = compare(root, [rtl_record], [qemu_record])
            assert result.returncode == 1, result.stdout
            assert f"field={field}" in result.stdout, result.stdout

        result = compare(root, [alias_pairs[0][0]], [alias_pairs[0][1]],
                         stream=False)
        assert result.returncode == 1, result.stdout
        assert "field=pc" in result.stdout, result.stdout

        vector_fault = record(0, "0000002c", "01086020", "00000000")
        vector_fault.update({"gpr_we": 0, "gpr_addr": 0, "except": 1,
                             "except_code": 12, "next_pc": "00000180"})
        qemu_vector_fault = dict(vector_fault, next_pc="80000180")
        vector_handler = record(1, "00000180", "0c0000dc", "00000188")
        vector_handler["gpr_addr"] = 31
        qemu_vector_handler = record(1, "80000180", "0c0000dc", "80000188")
        qemu_vector_handler["gpr_addr"] = 31
        vector_handler_next = record(2, "00000184", "24420001", "00000030")
        qemu_vector_handler_next = record(
            2, "80000184", "24420001", "00000030")
        vector_eret = record(3, "00000370", "42000018", "00000000")
        vector_eret.update({"gpr_we": 0, "gpr_addr": 0, "eret": 1,
                            "next_pc": "00000030"})
        qemu_vector_eret = record(3, "80000370", "42000018", "00000000")
        qemu_vector_eret.update({"gpr_we": 0, "gpr_addr": 0, "eret": 1,
                                 "next_pc": "00000030"})
        vector_return = record(4, "00000030", "00000000", "00000000")
        qemu_vector_return = dict(vector_return)
        vector_trace_rtl = [vector_fault, vector_handler,
                            vector_handler_next, vector_eret, vector_return]
        vector_trace_qemu = [qemu_vector_fault, qemu_vector_handler,
                             qemu_vector_handler_next, qemu_vector_eret,
                             qemu_vector_return]
        for stream in (True, False):
            result = compare(root, vector_trace_rtl, vector_trace_qemu,
                             stream=stream)
            assert result.returncode == 0, result.stdout
            wrong_link = dict(qemu_vector_handler, gpr_data="8000018c")
            result = compare(root, vector_trace_rtl,
                             [qemu_vector_fault, wrong_link,
                              qemu_vector_handler_next, qemu_vector_eret,
                              qemu_vector_return], stream=stream)
            assert result.returncode == 1, result.stdout
            assert "field=gpr_data" in result.stdout, result.stdout

            unrelated_alias_write = dict(qemu_vector_handler_next,
                                         gpr_data="80000030")
            result = compare(root, vector_trace_rtl,
                             [qemu_vector_fault, qemu_vector_handler,
                              unrelated_alias_write, qemu_vector_eret,
                              qemu_vector_return], stream=stream)
            assert result.returncode == 1, result.stdout
            assert "field=gpr_data" in result.stdout, result.stdout

            wrong_return_alias = dict(qemu_vector_return,
                                      pc="80000030", next_pc="80000034")
            result = compare(root, vector_trace_rtl,
                             vector_trace_qemu[:-1] + [wrong_return_alias],
                             stream=stream)
            assert result.returncode == 1, result.stdout
            assert "field=pc" in result.stdout, result.stdout

        fault_access = record(0, "80001000", "8c420000", "00000000")
        fault_access.update({
            "gpr_we": 0, "gpr_addr": 0, "except": 1, "except_code": 2,
            "next_pc": "88000180", "mem_valid": 1, "mem_read": 1,
            "mem_addr": "88002000",
        })
        fault_address_mutation = dict(fault_access, mem_addr="88003000")
        result = compare(root, [fault_access], [fault_address_mutation])
        assert result.returncode == 1, result.stdout
        assert "field=mem_addr" in result.stdout, result.stdout
        result = compare(root, [fault_access], [fault_address_mutation],
                         stream=False)
        assert result.returncode == 1, result.stdout
        assert "field=mem_addr" in result.stdout, result.stdout

        # A producer may not observe a faulting transaction at the same
        # pipeline boundary. Compare the address only when both report it.
        result = compare(root, [fault_access],
                         [dict(fault_access, mem_valid=0, mem_read=0)])
        assert result.returncode == 0, result.stdout

        faulting_gpr_write = dict(fault_access, gpr_we=1, gpr_addr=2,
                                  gpr_data="00000001")
        result = compare(root, [faulting_gpr_write], [fault_access])
        assert result.returncode == 1, result.stdout
        assert "field=gpr_we" in result.stdout, result.stdout

        faulting_cp0_write = record(0, "80001000", "40825800", "00000000")
        faulting_cp0_write.update({"cp0_we": 1, "cp0_addr": 11,
                                   "cp0_sel": 0, "cp0_data": "00000001",
                                   "except": 1, "except_code": 4,
                                   "next_pc": "88000180"})
        no_faulting_cp0_write = dict(faulting_cp0_write, cp0_we=0, cp0_addr=0,
                                     cp0_sel=0, cp0_data="00000000")
        result = compare(root, [faulting_cp0_write],
                         [no_faulting_cp0_write])
        assert result.returncode == 1, result.stdout
        assert "field=cp0_we" in result.stdout, result.stdout

        merge_store = record(0, "80001000", "a8430001", "00000000")
        merge_store.update({"gpr_we": 0, "gpr_addr": 0, "mem_valid": 1,
                            "mem_write": 1, "mem_addr": "88002001",
                            "mem_wdata": "11223344"})
        result = compare(root, [merge_store],
                         [dict(merge_store, mem_wdata="11223345")])
        assert result.returncode == 1, result.stdout
        assert "field=mem_wdata" in result.stdout, result.stdout
        result = compare(root, [merge_store],
                         [dict(merge_store, mem_addr="88002002")])
        assert result.returncode == 1, result.stdout
        assert "field=mem_addr" in result.stdout, result.stdout
        result = compare(root, [merge_store],
                         [dict(merge_store, mem_wdata="11223345")],
                         stream=False)
        assert result.returncode == 1, result.stdout
        assert "field=mem_wdata" in result.stdout, result.stdout

        double_store = record(0, "80001000", "f4030000", "00000000")
        double_store.update({"gpr_we": 0, "gpr_addr": 0, "mem_valid": 1,
                             "mem_write": 1, "mem_addr": "88002000",
                             "mem_wdata": "55667788",
                             "mem_wdata_hi": "11223344"})
        result = compare(root, [double_store], [double_store])
        assert result.returncode == 0, result.stdout
        result = compare(root, [double_store],
                         [dict(double_store, mem_wdata="55667789")])
        assert result.returncode == 1, result.stdout
        assert "field=mem_wdata" in result.stdout, result.stdout
        result = compare(root, [double_store],
                         [dict(double_store, mem_wdata_hi="11223345")])
        assert result.returncode == 1, result.stdout
        assert "field=mem_wdata_hi" in result.stdout, result.stdout
        result = compare(root, [double_store],
                         [dict(double_store, mem_wdata_hi="11223345")],
                         stream=False)
        assert result.returncode == 1, result.stdout
        assert "field=mem_wdata_hi" in result.stdout, result.stdout
        cop1x_store = dict(double_store, instr="4c441809")
        result = compare(root, [cop1x_store],
                         [dict(cop1x_store, mem_wdata_hi="11223345")])
        assert result.returncode == 1, result.stdout
        assert "field=mem_wdata_hi" in result.stdout, result.stdout
        missing_hi = dict(double_store)
        del missing_hi["mem_wdata_hi"]
        result = compare(root, [missing_hi], [missing_hi])
        assert result.returncode == 1, result.stdout
        assert "field=mem_wdata_hi" in result.stdout, result.stdout
        result = compare(root, [missing_hi], [missing_hi], stream=False)
        assert result.returncode == 1, result.stdout
        assert "field=mem_wdata_hi" in result.stdout, result.stdout

        full_state = schema_v2(record(0, "80001000", "24420001",
                                      "00000001"),
                               "1122334455667788")
        for stream in (True, False):
            result = compare(root, [full_state], [dict(full_state)],
                             stream=stream)
            assert result.returncode == 0, result.stdout

            result = compare(root, [full_state],
                             [dict(full_state,
                                   gpr_state="1" + full_state["gpr_state"][1:])],
                             stream=stream)
            assert result.returncode == 1, result.stdout
            assert "field=gpr_state" in result.stdout, result.stdout

            result = compare(root, [full_state],
                             [dict(full_state, hilo_state="1122334455667789")],
                             stream=stream)
            assert result.returncode == 1, result.stdout
            assert "field=hilo_state" in result.stdout, result.stdout

        special2_mul = schema_v2(
            record(0, "80001000", "70642802", "00000058"),
            "1122334455667788")
        special2_mul.update({"gpr_addr": 5})
        special2_mul = with_gpr_word(special2_mul, 5, "00000058")
        mflo_undefined_rtl = schema_v2(
            record(1, "80001004", "00001812", "000007d0"),
            "00000000000007d0")
        mflo_undefined_rtl.update({"gpr_addr": 3})
        mflo_undefined_rtl = with_gpr_word(mflo_undefined_rtl, 3,
                                           "000007d0")
        mflo_undefined_qemu = dict(mflo_undefined_rtl,
                                   gpr_data="00000000",
                                   hilo_state="0000000000000000")
        mflo_undefined_qemu = with_gpr_word(mflo_undefined_qemu, 3,
                                            "00000000")
        mflo_store_rtl = schema_v2(
            record(2, "80001008", "afa300a8", "00000000"),
            "00000000000007d0")
        mflo_store_rtl.update({"gpr_we": 0, "gpr_addr": 0,
                               "mem_valid": 1, "mem_write": 1,
                               "mem_addr": "00001000",
                               "mem_wdata": "000007d0"})
        mflo_store_qemu = dict(mflo_store_rtl, mem_wdata="00000000")
        mflo_load_rtl = schema_v2(
            record(3, "8000100c", "8ca40000", "000007d0"),
            "00000000000007d0")
        mflo_load_rtl.update({"gpr_addr": 4, "mem_valid": 1,
                              "mem_read": 1, "mem_addr": "00001000",
                              "mem_rdata": "000007d0"})
        mflo_load_rtl = with_gpr_word(mflo_load_rtl, 3, "000007d0")
        mflo_load_rtl = with_gpr_word(mflo_load_rtl, 4, "000007d0")
        mflo_load_qemu = dict(mflo_load_rtl, gpr_data="00000000",
                              mem_rdata="00000000")
        mflo_load_qemu = with_gpr_word(mflo_load_qemu, 3, "00000000")
        mflo_load_qemu = with_gpr_word(mflo_load_qemu, 4, "00000000")
        after_mflo_rtl = schema_v2(
            record(4, "80001010", "24420001", "00000001"),
            "00000000000007d0")
        after_mflo_rtl = with_gpr_word(after_mflo_rtl, 2, "00000001")
        after_mflo_rtl = with_gpr_word(after_mflo_rtl, 3, "000007d0")
        after_mflo_rtl = with_gpr_word(after_mflo_rtl, 4, "000007d0")
        after_mflo_qemu = dict(after_mflo_rtl,
                               hilo_state="0000000000000000")
        after_mflo_qemu = with_gpr_word(after_mflo_qemu, 3, "00000000")
        after_mflo_qemu = with_gpr_word(after_mflo_qemu, 4, "00000000")
        mflo_overwrite = schema_v2(
            record(5, "80001014", "24030001", "00000001"),
            "0000000000000000")
        mflo_overwrite.update({"gpr_addr": 3})
        mflo_overwrite = with_gpr_word(mflo_overwrite, 3, "00000001")
        defined_store = schema_v2(
            record(6, "80001018", "afa300a8", "00000000"),
            "0000000000000000")
        defined_store.update({"gpr_we": 0, "gpr_addr": 0,
                              "mem_valid": 1, "mem_write": 1,
                              "mem_addr": "00001000",
                              "mem_wdata": "00000001"})
        defined_store = with_gpr_word(defined_store, 3, "00000001")
        defined_store = with_gpr_word(defined_store, 4, "000007d0")
        defined_store_qemu = with_gpr_word(dict(defined_store), 4,
                                           "00000000")
        defined_load = schema_v2(
            record(7, "8000101c", "8ca40000", "00000001"),
            "0000000000000000")
        defined_load.update({"gpr_addr": 4, "mem_valid": 1,
                             "mem_read": 1, "mem_addr": "00001000",
                             "mem_rdata": "00000001"})
        defined_load = with_gpr_word(defined_load, 3, "00000001")
        defined_load = with_gpr_word(defined_load, 4, "00000001")
        defined_load_qemu = dict(defined_load)
        undefined_hilo_rtl = [special2_mul, mflo_undefined_rtl,
                              mflo_store_rtl, mflo_load_rtl,
                              after_mflo_rtl, mflo_overwrite,
                              defined_store, defined_load]
        undefined_hilo_qemu = [dict(special2_mul), mflo_undefined_qemu,
                               mflo_store_qemu, mflo_load_qemu,
                               after_mflo_qemu, dict(mflo_overwrite),
                               defined_store_qemu, defined_load_qemu]
        for stream in (True, False):
            result = compare(root, undefined_hilo_rtl,
                             undefined_hilo_qemu, stream=stream)
            assert result.returncode == 0, result.stdout

            unrelated_diff = with_gpr_word(after_mflo_qemu, 18,
                                           "00000001")
            qemu_unrelated = list(undefined_hilo_qemu)
            qemu_unrelated[4] = unrelated_diff
            result = compare(root, undefined_hilo_rtl, qemu_unrelated,
                             stream=stream)
            assert result.returncode == 1, result.stdout
            assert "field=gpr_state" in result.stdout, result.stdout

            wrong_overwrite = dict(mflo_overwrite, gpr_data="00000002")
            wrong_overwrite = with_gpr_word(wrong_overwrite, 3,
                                            "00000002")
            qemu_wrong_overwrite = list(undefined_hilo_qemu)
            qemu_wrong_overwrite[5] = wrong_overwrite
            result = compare(root, undefined_hilo_rtl, qemu_wrong_overwrite,
                             stream=stream)
            assert result.returncode == 1, result.stdout
            assert "field=gpr_data" in result.stdout, result.stdout

            wrong_store_address = dict(mflo_store_qemu,
                                       mem_addr="00001004")
            qemu_wrong_store_address = list(undefined_hilo_qemu)
            qemu_wrong_store_address[2] = wrong_store_address
            result = compare(root, undefined_hilo_rtl,
                             qemu_wrong_store_address, stream=stream)
            assert result.returncode == 1, result.stdout
            assert "field=mem_addr" in result.stdout, result.stdout

            wrong_defined_store = dict(defined_store_qemu,
                                       mem_wdata="00000002")
            qemu_wrong_defined_store = list(undefined_hilo_qemu)
            qemu_wrong_defined_store[6] = wrong_defined_store
            result = compare(root, undefined_hilo_rtl,
                             qemu_wrong_defined_store, stream=stream)
            assert result.returncode == 1, result.stdout
            assert "field=mem_wdata" in result.stdout, result.stdout

            wrong_defined_load = dict(defined_load_qemu,
                                      gpr_data="00000002",
                                      mem_rdata="00000002")
            wrong_defined_load = with_gpr_word(wrong_defined_load, 4,
                                               "00000002")
            qemu_wrong_defined_load = list(undefined_hilo_qemu)
            qemu_wrong_defined_load[7] = wrong_defined_load
            result = compare(root, undefined_hilo_rtl,
                             qemu_wrong_defined_load, stream=stream)
            assert result.returncode == 1, result.stdout
            assert "field=gpr_data" in result.stdout, result.stdout

            defined_mult = schema_v2(
                record(0, "80002000", "00640018", "00000000"),
                "0000000000000002")
            defined_mult.update({"gpr_we": 0, "gpr_addr": 0})
            defined_mflo = schema_v2(
                record(1, "80002004", "00001812", "00000002"),
                "0000000000000002")
            defined_mflo.update({"gpr_addr": 3})
            wrong_defined_mflo = dict(defined_mflo,
                                      gpr_data="00000003",
                                      hilo_state="0000000000000003")
            wrong_defined_mflo = with_gpr_word(
                wrong_defined_mflo, 3, "00000003")
            result = compare(root, [defined_mult, defined_mflo],
                             [dict(defined_mult), wrong_defined_mflo],
                             stream=stream)
            assert result.returncode == 1, result.stdout
            assert "field=gpr_data" in result.stdout, result.stdout

            mthi = schema_v2(
                record(1, "80003004", "00c00011", "00000000"),
                "1122334400000000")
            mthi.update({"gpr_we": 0, "gpr_addr": 0})
            mthi = with_gpr_word(mthi, 6, "11223344")
            mflo_r3 = schema_v2(
                record(2, "80003008", "00001812", "000007d0"),
                "11223344000007d0")
            mflo_r3.update({"gpr_addr": 3})
            mflo_r3 = with_gpr_word(mflo_r3, 3, "000007d0")
            mflo_r3_qemu = dict(mflo_r3, gpr_data="00000000",
                                hilo_state="1122334400000000")
            mflo_r3_qemu = with_gpr_word(mflo_r3_qemu, 3, "00000000")
            mtlo_r3 = schema_v2(
                record(3, "8000300c", "00600013", "00000000"),
                "11223344000007d0")
            mtlo_r3.update({"gpr_we": 0, "gpr_addr": 0})
            mtlo_r3 = with_gpr_word(mtlo_r3, 3, "000007d0")
            mtlo_r3_qemu = dict(mtlo_r3,
                                hilo_state="1122334400000000")
            mtlo_r3_qemu = with_gpr_word(mtlo_r3_qemu, 3, "00000000")
            mflo_r4 = schema_v2(
                record(4, "80003010", "00002012", "000007d0"),
                "11223344000007d0")
            mflo_r4.update({"gpr_addr": 4})
            mflo_r4 = with_gpr_word(mflo_r4, 3, "000007d0")
            mflo_r4 = with_gpr_word(mflo_r4, 4, "000007d0")
            mflo_r4_qemu = dict(mflo_r4, gpr_data="00000000",
                                hilo_state="1122334400000000")
            mflo_r4_qemu = with_gpr_word(mflo_r4_qemu, 3, "00000000")
            mflo_r4_qemu = with_gpr_word(mflo_r4_qemu, 4, "00000000")
            mtlo_rtl = [special2_mul, mthi, mflo_r3, mtlo_r3, mflo_r4]
            mtlo_qemu = [dict(special2_mul), dict(mthi), mflo_r3_qemu,
                         mtlo_r3_qemu, mflo_r4_qemu]
            result = compare(root, mtlo_rtl, mtlo_qemu, stream=stream)
            assert result.returncode == 0, result.stdout

            wrong_mthi = dict(mthi, hilo_state="1122334500000000")
            result = compare(root,
                             [special2_mul, mthi, mflo_r3, mtlo_r3, mflo_r4],
                             [dict(special2_mul), wrong_mthi, mflo_r3_qemu,
                              mtlo_r3_qemu, mflo_r4_qemu],
                             stream=stream)
            assert result.returncode == 1, result.stdout
            assert "field=hilo_state" in result.stdout, result.stdout

        mul_rtl = schema_v2(
            record(0, "80001000", "70522002", "00000058"),
            "0000000000000000")
        mul_rtl["gpr_addr"] = 4
        mul_rtl = with_gpr_word(mul_rtl, 4, "00000058")
        mul_qemu = dict(mul_rtl, hilo_state="0000000000000058")
        after_mul_rtl = schema_v2(
            record(1, "80001004", "24420001", "00000001"),
            "0000000000000000")
        after_mul_rtl = with_gpr_word(after_mul_rtl, 4, "00000058")
        after_mul_rtl = with_gpr_word(after_mul_rtl, 2, "00000001")
        after_mul_qemu = dict(after_mul_rtl,
                              hilo_state="0000000000000058")
        for stream in (True, False):
            result = compare(root, [mul_rtl, after_mul_rtl],
                             [mul_qemu, after_mul_qemu], stream=stream)
            assert result.returncode == 0, result.stdout

            changed_gpr_state = with_gpr_word(after_mul_qemu, 5,
                                              "00000001")
            result = compare(root, [mul_rtl, after_mul_rtl],
                             [mul_qemu, changed_gpr_state], stream=stream)
            assert result.returncode == 1, result.stdout
            assert "field=gpr_state" in result.stdout, result.stdout

            mult_rtl = dict(after_mul_rtl, retire_seq=2,
                            pc="80001008", instr="00640018",
                            next_pc="8000100c", gpr_we=0, gpr_addr=0,
                            gpr_data="00000000",
                            hilo_state="0000000000000002")
            mult_qemu = dict(mult_rtl)
            after_mult_rtl = schema_v2(
                record(3, "8000100c", "24420001", "00000002"),
                "0000000000000002")
            after_mult_rtl = with_gpr_word(after_mult_rtl, 4,
                                           "00000058")
            after_mult_rtl = with_gpr_word(after_mult_rtl, 2,
                                           "00000002")
            after_mult_qemu = dict(after_mult_rtl,
                                   hilo_state="0000000000000003")
            result = compare(root,
                             [mul_rtl, after_mul_rtl, mult_rtl,
                              after_mult_rtl],
                             [mul_qemu, after_mul_qemu, mult_qemu,
                              after_mult_qemu], stream=stream)
            assert result.returncode == 1, result.stdout
            assert "field=hilo_state" in result.stdout, result.stdout

        missing_gprs = dict(full_state)
        del missing_gprs["gpr_state"]
        for stream in (True, False):
            result = compare(root, [missing_gprs], [missing_gprs],
                             stream=stream)
            assert result.returncode == 2, result.stdout
            assert "missing fields: gpr_state" in result.stdout, result.stdout

        validator_trace = root / "schema_v2.jsonl"
        write_trace(validator_trace, [full_state])
        result = subprocess.run(
            [sys.executable, str(TRACE_VALIDATOR), "validate-trace",
             str(validator_trace), "--max-records", "10"],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            check=False)
        assert result.returncode == 0, result.stdout
        assert "LINUX_DIFFERENTIAL_TRACE_VALID records=1" in result.stdout

        write_trace(validator_trace, [missing_gprs])
        result = subprocess.run(
            [sys.executable, str(TRACE_VALIDATOR), "validate-trace",
             str(validator_trace), "--max-records", "10"],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            check=False)
        assert result.returncode == 1, result.stdout
        assert "missing fields: gpr_state" in result.stdout

    events = [
        {"pc": "88001000", "instr": "40824800", "next_pc": "88001004"},
        {"pc": "88001004", "instr": "40835800", "next_pc": "88001008"},
    ]
    states = [
        register_state("88001000", r2="0402001d", r3="0401b6af"),
        register_state("88001004", r2="0402001d", r3="0401b6af"),
        register_state("88001008", r2="0402001d", r3="0401b6af"),
    ]
    converted = list(CONVERTER.convert(events, states))
    assert [(item["cp0_addr"], item["cp0_data"]) for item in converted] == [
        (9, "0402001d"), (11, "0401b6af")]

    fault_event = [{"pc": "88001000", "instr": "40824800",
                    "next_pc": "88000180"}]
    fault_states = [
        register_state("88001000", r2="0402001d"),
        register_state("88000180", cause="0000002c"),
    ]
    fault_record = list(CONVERTER.convert(fault_event, fault_states))[0]
    assert fault_record["except"] == 1
    assert fault_record["cp0_we"] == 0

    print("TRACE_COMPARE_STREAM_TEST_PASS")


if __name__ == "__main__":
    main()
