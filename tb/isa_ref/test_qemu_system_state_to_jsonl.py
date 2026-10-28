#!/usr/bin/env python3
"""Regression tests for QEMU system retire conversion decisions."""

import importlib.util
import os
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("qemu_system_state_to_jsonl.py")
SPEC = importlib.util.spec_from_file_location("qemu_system_state_to_jsonl", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)
COMPARE_PATH = Path(__file__).with_name("trace_compare.py")
COMPARE_SPEC = importlib.util.spec_from_file_location("trace_compare", COMPARE_PATH)
COMPARE = importlib.util.module_from_spec(COMPARE_SPEC)
assert COMPARE_SPEC.loader is not None
COMPARE_SPEC.loader.exec_module(COMPARE)


def encode_special2(rs, rt, rd, funct, sa=0):
    return (0x1C << 26) | (rs << 21) | (rt << 16) | (rd << 11) | (sa << 6) | funct


def test_special2_accumulate_has_no_gpr_destination():
    for funct in (0x00, 0x01, 0x04, 0x05):
        assert MODULE.gpr_destination(encode_special2(3, 4, 0, funct)) is None


def test_retire_record_carries_handler_entry_cause_and_epc():
    before = {f"r{index}": "00000000" for index in range(32)}
    before.update({f"fpr{index}": "00000000" for index in range(32)})
    before.update({"cause": "00000008", "epc": "00400374"})
    after = dict(before)
    states = [{"pc": "88e08000", "regs": before},
              {"pc": "88e08004", "regs": after}]
    event = {"pc": "88e08000", "instr": "401b2000",
             "next_pc": "88e08004"}

    record = list(MODULE.convert([event], states))[0]

    assert record["qemu_cause"] == "00000008"
    assert record["qemu_epc"] == "00400374"


def test_mfc0_cause_preserves_branch_delay_bit_from_qemu_state():
    def regs(**updates):
        value = {f"r{index}": "00000000" for index in range(32)}
        value.update({f"fpr{index}": "00000000" for index in range(32)})
        value.update({"cause": "00000000", "epc": "00000000"})
        value.update(updates)
        return value

    events = [
        {"pc": "0000000c", "instr": "10000002", "next_pc": "00000010"},
        {"pc": "00000010", "instr": "0000000c", "next_pc": "80000180"},
        {"pc": "80000180", "instr": "401a6800", "next_pc": "80000184"},
    ]
    states = [
        {"pc": "0000000c", "regs": regs()},
        {"pc": "00000010", "regs": regs()},
        {"pc": "80000180", "regs": regs(cause="80000020", epc="0000000c")},
        {"pc": "80000184", "regs": regs(cause="80000020", epc="0000000c",
                                            r26="80000020")},
    ]

    result = list(MODULE.convert(events, states))

    assert result[1]["bd"] == 1
    assert result[2]["gpr_data"] == "80000020"


def test_special2_rd_operations_keep_their_destination():
    for funct in (0x02, 0x20, 0x21):
        assert MODULE.gpr_destination(encode_special2(3, 4, 7, funct)) == 7


def test_special2_mul_keeps_qemu_hilo_choice():
    """SPECIAL2 MUL does not invent an architectural HI/LO result."""
    def regs(**updates):
        value = {f"r{index}": "00000000" for index in range(32)}
        value.update({f"fpr{index}": "00000000" for index in range(32)})
        value.update({"cause": "00000000", "epc": "00000000",
                      "index": "00000000", "pagemask": "00000000",
                      "entryhi": "00000000", "status": "00000000",
                      "hi": "00000012", "lo": "00000034"})
        value.update(updates)
        return value

    events = [
        {"pc": "00000100", "instr": "%08x" % encode_special2(3, 4, 2, 2),
         "next_pc": "00000104"},
        {"pc": "00000104", "instr": "00002812", "next_pc": "00000108"},
    ]
    states = [
        {"pc": "00000100", "regs": regs(r3="0000007d", r4="00000010")},
        {"pc": "00000104", "regs": regs(r2="000007d0")},
        {"pc": "00000108", "regs": regs(r5="00000034")},
    ]
    result = list(MODULE.convert(events, states))
    assert result[0]["gpr_data"] == "000007d0"
    assert result[1]["gpr_data"] == "00000034"


def test_mult_hilo_replay_survives_interrupt_frame_memory_roundtrip():
    """Synthetic HI saved by MFHI must be restored through LW/MTHI."""
    def regs(**updates):
        value = {f"r{index}": "00000000" for index in range(32)}
        value.update({f"fpr{index}": "00000000" for index in range(32)})
        value.update({"cause": "00000000", "epc": "00000000",
                      "index": "00000000", "pagemask": "00000000",
                      "entryhi": "00000000", "status": "00000000",
                      "hi": "00000009", "lo": "00000064"})
        value.update(updates)
        return value

    events = [
        {"pc": "00000200", "instr": "00640018",
         "next_pc": "00000204"},
        {"pc": "00000204", "instr": "00001810", "next_pc": "00000208"},
        {"pc": "00000208", "instr": "afa300a4", "next_pc": "0000020c",
         "mem_valid": 1, "mem_write": 1, "mem_addr": "00001000",
         "mem_value": "00000000", "mem_size": 4},
        {"pc": "0000020c", "instr": "8fb800a4", "next_pc": "00000210",
         "mem_valid": 1, "mem_read": 1, "mem_addr": "00001000",
         "mem_value": "00000009", "mem_size": 4},
        {"pc": "00000210", "instr": "03000011", "next_pc": "00000214"},
        {"pc": "00000214", "instr": "00002010", "next_pc": "00000218"},
    ]
    states = [
        {"pc": "00000200", "regs": regs(r3="80000000", r4="00000002")},
        {"pc": "00000204", "regs": regs(r2="00000000")},
        {"pc": "00000208", "regs": regs(r3="00000009")},
        {"pc": "0000020c", "regs": regs()},
        {"pc": "00000210", "regs": regs(r24="00000009")},
        {"pc": "00000214", "regs": regs(r24="00000009")},
        {"pc": "00000218", "regs": regs(r4="00000009")},
    ]

    result = list(MODULE.convert(events, states))
    assert result[1]["gpr_data"] == "ffffffff"
    assert result[2]["mem_wdata"] == "ffffffff"
    assert result[3]["gpr_data"] == "ffffffff"
    assert result[4]["gpr_we"] == 0
    assert result[5]["gpr_data"] == "ffffffff"


def test_replay_bd_survives_general_to_vic_vector_handoff():
    """A VIC jump delay slot must not clear BD recovered at the first vector."""
    def regs(**updates):
        value = {f"r{index}": "00000000" for index in range(32)}
        value.update({f"fpr{index}": "00000000" for index in range(32)})
        value.update({"cause": "00000000", "epc": "00000000",
                      "index": "00000000", "pagemask": "00000000",
                      "entryhi": "00000000", "status": "00000000"})
        value.update(updates)
        return value

    events = [
        {"pc": "00000100", "instr": "00000000", "next_pc": "00000104"},
        {"pc": "00000104", "instr": "00000000", "next_pc": "80000180"},
        {"pc": "80000180", "instr": "0c0000dc", "next_pc": "80000184"},
        {"pc": "80000184", "instr": "afa20004", "next_pc": "80000370"},
        {"pc": "80000370", "instr": "40026800", "next_pc": "80000374"},
        {"pc": "80000374", "instr": "00021082", "next_pc": "80000378"},
    ]
    states = [
        {"pc": "00000100", "regs": regs()},
        {"pc": "00000104", "regs": regs()},
        {"pc": "80000180", "regs": regs(cause="80000400")},
        {"pc": "80000184", "regs": regs(cause="80000400")},
        {"pc": "80000370", "regs": regs(cause="80000400")},
        {"pc": "80000374", "regs": regs(cause="80000400", r2="00000400")},
        {"pc": "80000378", "regs": regs(cause="80000400", r2="00000100")},
    ]
    result = list(MODULE.convert(events, states))
    assert result[4]["gpr_data"] == "80000400"
    assert result[5]["gpr_data"] == "20000100"


def test_tlb_refill_reconstructs_faulting_store():
    def regs(**updates):
        value = {f"r{index}": "00000000" for index in range(32)}
        value.update({f"fpr{index}": "00000000" for index in range(32)})
        value.update({"cause": "00000000", "epc": "00000000",
                      "index": "00000000", "pagemask": "00000000",
                      "entryhi": "00000000", "status": "00000000"})
        value.update(updates)
        return value

    events = [{"pc": "88d0bfd8", "instr": "ac430010",
               "next_pc": "88e08000", "mem_valid": 0}]
    states = [
        {"pc": "88d0bfd8", "regs": regs(r2="c0000000", r3="ffffffff")},
        {"pc": "88e08000", "regs": regs()},
    ]
    result = list(MODULE.convert(events, states))
    assert result[0]["except"] == 1
    assert result[0]["except_code"] == 3
    assert result[0]["mem_valid"] == 1
    assert result[0]["mem_write"] == 1
    assert result[0]["mem_addr"] == "c0000010"
    assert result[0]["mem_wdata"] == "ffffffff"
    assert result[0]["mem_rdata"] == "00000000"


def test_merge_memory_uses_original_effective_address():
    def regs(**updates):
        value = {f"r{index}": "00000000" for index in range(32)}
        value.update({f"fpr{index}": "00000000" for index in range(32)})
        value.update({"cause": "00000000", "epc": "00000000",
                      "index": "00000000", "pagemask": "00000000",
                      "entryhi": "00000000", "status": "00000000"})
        value.update(updates)
        return value

    for opcode in (0x22, 0x26):
        instr = (opcode << 26) | (2 << 21) | (3 << 16) | 1
        events = [{"pc": "80001000", "instr": f"{instr:08x}",
                   "next_pc": "80001004", "mem_valid": 1,
                   "mem_read": 1, "mem_addr": "88002000",
                   "mem_value": "aabbccdd", "mem_size": 4}]
        states = [
            {"pc": "80001000", "regs": regs(r2="88002000",
                                                  r3="00000000")},
            {"pc": "80001004", "regs": regs(r2="88002000",
                                                  r3="aabbccdd")},
        ]
        result = list(MODULE.convert(events, states))[0]
        assert result["mem_valid"] == 1
        assert result["mem_read"] == 1
        assert result["mem_addr"] == "88002001"

    for opcode in (0x2a, 0x2e):
        instr = (opcode << 26) | (2 << 21) | (3 << 16) | 1
        events = [{"pc": "80001000", "instr": f"{instr:08x}",
                   "next_pc": "80001004", "mem_valid": 1,
                   "mem_write": 1, "mem_addr": "88002003",
                   "mem_value": "00000022", "mem_size": 1}]
        states = [
            {"pc": "80001000", "regs": regs(r2="88002000",
                                                  r3="11223344")},
            {"pc": "80001004", "regs": regs(r2="88002000",
                                                  r3="11223344")},
        ]
        result = list(MODULE.convert(events, states))[0]
        assert result["mem_valid"] == 1
        assert result["mem_write"] == 1
        assert result["mem_addr"] == "88002001"
        assert result["mem_wdata"] == "11223344"


def test_double_store_preserves_both_words():
    before = {f"r{index}": "00000000" for index in range(32)}
    after = dict(before)
    before["r2"] = after["r2"] = "88002000"
    states = [{"pc": "80001000", "regs": before},
              {"pc": "80001004", "regs": after}]
    for instr in ("f4430000", "4c441809"):
        event = {"pc": "80001000", "instr": instr,
                 "next_pc": "80001004", "mem_valid": 1, "mem_write": 1,
                 "mem_addr": "88002000", "mem_value": "55667788",
                 "mem_value_hi": "11223344", "mem_size": 8}
        record = list(MODULE.convert([event], states))[0]
        assert record["mem_wdata"] == "55667788"
        assert record["mem_wdata_hi"] == "11223344"

    del event["mem_value_hi"]
    try:
        list(MODULE.convert([event], states))
    except ValueError as exc:
        assert "complete 64-bit QEMU memory value" in str(exc)
    else:
        raise AssertionError("double store accepted without its upper data word")


def test_general_address_exception_reconstructs_faulting_access():
    def regs(**updates):
        value = {f"r{index}": "00000000" for index in range(32)}
        value.update({f"fpr{index}": "00000000" for index in range(32)})
        value.update({"cause": "00000000", "epc": "00000000",
                      "index": "00000000", "pagemask": "00000000",
                      "entryhi": "00000000", "status": "00000000"})
        value.update(updates)
        return value

    events = [{"pc": "80001000", "instr": "8c420001",
               "next_pc": "80000180"}]
    states = [
        {"pc": "80001000", "regs": regs(r2="88002000")},
        {"pc": "80000180", "regs": regs(cause="00000010")},
    ]
    result = list(MODULE.convert(events, states))[0]
    assert result["except"] == 1
    assert result["except_code"] == 4
    assert result["mem_valid"] == 1
    assert result["mem_read"] == 1
    assert result["mem_addr"] == "88002001"


def test_vectored_timer_interrupt_marks_async_boundary():
    def regs(**updates):
        value = {f"r{index}": "00000000" for index in range(32)}
        value.update({f"fpr{index}": "00000000" for index in range(32)})
        value.update({"cause": "00000000", "epc": "00000000",
                      "index": "00000000", "pagemask": "00000000",
                      "entryhi": "00000000", "status": "00000000"})
        value.update(updates)
        return value

    events = [{"pc": "88571dfc", "instr": "8c420044",
               "next_pc": "88e08200", "mem_valid": 1, "mem_read": 1,
               "mem_value": "00000000", "mem_size": 4}]
    states = [
        {"pc": "88571dfc", "regs": regs(r2="88a9dfe0")},
        {"pc": "88e08200", "regs": regs(r2="00000000",
                                          cause="4080800c",
                                          status="0040ff03")},
    ]
    result = list(MODULE.convert(events, states))
    assert result[0]["except"] == 1
    assert result[0]["except_code"] == 0
    assert result[0]["gpr_we"] == 1
    assert result[0]["gpr_addr"] == 2
    assert COMPARE.is_async_interrupt_boundary(result[0])
    rtl_boundary = dict(result[0])
    rtl_boundary.update({"except": 0, "next_pc": "88571e00"})
    vector_record = {"pc": "88e08200"}
    fields = COMPARE.stream_fields(
        rtl_boundary, result[0], None, None, vector_record, vector_record, None)
    assert "next_pc" not in fields
    assert "gpr_data" in fields
    assert "mem_rdata" in fields


def test_async_irq_boundary_aligns_to_vectored_entry():
    boundary = {"pc": "88571e00", "instr": "10400005",
                "next_pc": "88e08200", "except": 1,
                "except_code": 0, "bd": 0}
    vector = {"pc": "88e08200", "instr": "0a0008e8",
              "next_pc": "88e08204"}
    following = {"pc": "88e08204", "instr": "00000000",
                 "next_pc": "880023a0"}
    rtl = [(0, vector), (1, following)]
    golden = [(0, boundary), (1, vector), (2, following)]

    aligned_rtl, aligned_golden = COMPARE.align_async_vector_window(rtl, golden)
    assert [record[1]["pc"] for record in aligned_rtl] == [
        "88e08200", "88e08204"]
    assert [record[1]["pc"] for record in aligned_golden] == [
        "88e08200", "88e08204"]
    assert COMPARE.async_boundary_reaches(boundary, "88e08200")
    assert not COMPARE.async_boundary_reaches(boundary, "88e08204")


def test_replay_bd_is_scoped_to_each_interrupt():
    def regs(**updates):
        value = {f"r{index}": "00000000" for index in range(32)}
        value.update({f"fpr{index}": "00000000" for index in range(32)})
        value.update({"cause": "00000000", "epc": "00000000",
                      "index": "00000000", "pagemask": "00000000",
                      "entryhi": "00000000", "status": "00000000"})
        value.update(updates)
        return value

    events = [
        {"pc": "00000100", "instr": "00000000", "next_pc": "80000200"},
        {"pc": "80000200", "instr": "40026800", "next_pc": "80000204"},
        {"pc": "80000204", "instr": "10000000", "next_pc": "80000208"},
        {"pc": "80000208", "instr": "00000000", "next_pc": "80000200"},
        {"pc": "80000200", "instr": "40026800", "next_pc": "80000204"},
    ]
    states = [
        {"pc": "00000100", "regs": regs()},
        {"pc": "80000200", "regs": regs(cause="c0808000")},
        {"pc": "80000204", "regs": regs(cause="c0808000", r2="40808000")},
        {"pc": "80000208", "regs": regs(cause="c0808000", r2="c0808000")},
        {"pc": "80000200", "regs": regs(cause="c0808000", r2="c0808000")},
        {"pc": "80000204", "regs": regs(cause="c0808000", r2="40808000")},
    ]
    result = list(MODULE.convert(events, states))
    assert result[1]["gpr_data"] == "c0808000"
    assert result[4]["gpr_data"] == "c0808000"


def test_direct_jal_target_is_not_tlb_refill():
    events = [
        {"pc": "88d16368", "instr": "0e345800", "next_pc": "88d1636c"},
        {"pc": "88d1636c", "instr": "02402825", "next_pc": "88d16000"},
    ]
    assert MODULE.is_direct_branch_to_next_pc(events, 1)


def test_jr_delay_slot_page_aligned_target_is_not_tlb_refill():
    def regs(**updates):
        value = {f"r{index}": "00000000" for index in range(32)}
        value.update({f"fpr{index}": "00000000" for index in range(32)})
        value.update({"cause": "00000000", "epc": "00000000",
                      "index": "00000000", "pagemask": "00000000",
                      "entryhi": "00000000", "status": "00000000"})
        value.update(updates)
        return value

    events = [
        {"pc": "88cfd4f8", "instr": "03e00008", "next_pc": "88cfd4fc"},
        {"pc": "88cfd4fc", "instr": "27bd0018", "next_pc": "88ced000"},
    ]
    states = [
        {"pc": "88cfd4f8", "regs": regs(r31="88ced000", r29="89425ea8")},
        {"pc": "88cfd4fc", "regs": regs(r31="88ced000", r29="89425ea8")},
        {"pc": "88ced000", "regs": regs(r31="88ced000", r29="89425ec0")},
    ]
    result = list(MODULE.convert(events, states))
    assert result[1]["except"] == 0
    assert result[1]["except_code"] == 0
    assert result[1]["gpr_addr"] == 29
    assert result[1]["gpr_data"] == "89425ec0"


def test_eret_page_aligned_target_is_not_tlb_refill():
    def regs(**updates):
        value = {f"r{index}": "00000000" for index in range(32)}
        value.update({f"fpr{index}": "00000000" for index in range(32)})
        value.update({"cause": "00000000", "epc": "881f0000",
                      "index": "00000000", "pagemask": "00000000",
                      "entryhi": "00000000", "status": "00000000"})
        value.update(updates)
        return value

    events = [{"pc": "88002264", "instr": "42000018",
               "next_pc": "881f0000"}]
    states = [
        {"pc": "88002264", "regs": regs()},
        {"pc": "881f0000", "regs": regs()},
    ]
    result = list(MODULE.convert(events, states))[0]
    assert result["next_pc"] == "881f0000"
    assert result["except"] == 0
    assert result["except_code"] == 0


def test_sequential_pc_ending_in_vector_offset_is_not_exception():
    def regs(**updates):
        value = {f"r{index}": "00000000" for index in range(32)}
        value.update({f"fpr{index}": "00000000" for index in range(32)})
        value.update({"cause": "00000000", "epc": "00000000",
                      "index": "00000000", "pagemask": "00000000",
                      "entryhi": "00000000", "status": "00000000"})
        value.update(updates)
        return value

    events = [{"pc": "88a3e17c", "instr": "8fb3003c",
               "next_pc": "88a3e180", "mem_valid": 1,
               "mem_read": 1, "mem_value": "88c39dd8"}]
    states = [
        {"pc": "88a3e17c", "regs": regs(r29="88c39d18")},
        {"pc": "88a3e180", "regs": regs(r19="88c39dd8")},
    ]
    result = list(MODULE.convert(events, states))
    assert result[0]["except"] == 0
    assert result[0]["gpr_we"] == 1
    assert result[0]["gpr_addr"] == 19


def test_schema_v2_emits_full_post_retire_gpr_and_hilo_state():
    def regs(pc, **updates):
        value = {f"r{index}": "00000000" for index in range(32)}
        value.update({f"fpr{index}": "00000000" for index in range(32)})
        value.update({"cause": "00000000", "epc": "00000000",
                      "index": "00000000", "pagemask": "00000000",
                      "entryhi": "00000000", "status": "00000000",
                      "hi": "00000000", "lo": "00000000"})
        value.update(updates)
        return {"pc": pc, "regs": value}

    previous_schema = os.environ.get("QEMU_TRACE_SCHEMA")
    os.environ["QEMU_TRACE_SCHEMA"] = "00020000"
    try:
        events = [{"pc": "00000100", "instr": "24220001",
                   "next_pc": "00000104"}]
        states = [regs("00000100", r1="00000005", hi="11223344",
                        lo="55667788"),
                  regs("00000104", r1="00000005", r2="00000006",
                        hi="11223344", lo="55667788")]
        record = list(MODULE.convert(events, states))[0]
    finally:
        if previous_schema is None:
            os.environ.pop("QEMU_TRACE_SCHEMA", None)
        else:
            os.environ["QEMU_TRACE_SCHEMA"] = previous_schema

    expected_gprs = {f"r{index}": "00000000" for index in range(32)}
    expected_gprs.update({"r1": "00000005", "r2": "00000006"})
    assert record["schema"] == "00020000"
    assert record["gpr_state"] == "".join(
        expected_gprs[f"r{index}"] for index in range(31, -1, -1))
    assert record["hilo_state"] == "1122334455667788"


if __name__ == "__main__":
    test_special2_accumulate_has_no_gpr_destination()
    test_mfc0_cause_preserves_branch_delay_bit_from_qemu_state()
    test_special2_rd_operations_keep_their_destination()
    test_special2_mul_keeps_qemu_hilo_choice()
    test_mult_hilo_replay_survives_interrupt_frame_memory_roundtrip()
    test_replay_bd_survives_general_to_vic_vector_handoff()
    test_tlb_refill_reconstructs_faulting_store()
    test_merge_memory_uses_original_effective_address()
    test_double_store_preserves_both_words()
    test_general_address_exception_reconstructs_faulting_access()
    test_vectored_timer_interrupt_marks_async_boundary()
    test_async_irq_boundary_aligns_to_vectored_entry()
    test_replay_bd_is_scoped_to_each_interrupt()
    test_direct_jal_target_is_not_tlb_refill()
    test_jr_delay_slot_page_aligned_target_is_not_tlb_refill()
    test_eret_page_aligned_target_is_not_tlb_refill()
    test_sequential_pc_ending_in_vector_offset_is_not_exception()
    test_schema_v2_emits_full_post_retire_gpr_and_hilo_state()
    print("qemu_system_state_to_jsonl tests: PASS")
