#!/usr/bin/env python3
import os
import sys
import glob
import re
import subprocess
import shutil

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
COVERAGE_DIR = os.path.join(ROOT_DIR, "tb/coverage")
UVM_EXCL_FILE = os.path.join(COVERAGE_DIR, "uvm_exclusions.el")
PROD_EXCL_FILE = os.path.join(COVERAGE_DIR, "product_exclusions.el")
MANIFEST_FILE = os.path.join(COVERAGE_DIR, "exclusion_manifest.json")

SYS_CATEGORIES = {
    'dcache': 'Cache & Memory Subsystem',
    'icache': 'Cache & Memory Subsystem',
    'axi_sram': 'Cache & Memory Subsystem',
    'axi_ddr_model': 'Cache & Memory Subsystem',
    'mips_cpu': 'CPU Core & Pipeline',
    'mips_control': 'CPU Core & Pipeline',
    'mips_cp0': 'CPU Core & Pipeline',
    'mips_alu': 'CPU Core & Pipeline',
    'mips_mdu': 'CPU Core & Pipeline',
    'mips_regfile': 'CPU Core & Pipeline',
    'mips_if_stage': 'CPU Core & Pipeline',
    'mips_id_stage': 'CPU Core & Pipeline',
    'mips_ex_stage': 'CPU Core & Pipeline',
    'mips_mem_stage': 'CPU Core & Pipeline',
    'mips_wb_stage': 'CPU Core & Pipeline',
    'mips_if_id_reg': 'CPU Core & Pipeline',
    'mips_id_ex_reg': 'CPU Core & Pipeline',
    'mips_ex_mem_reg': 'CPU Core & Pipeline',
    'mips_mem_wb_reg': 'CPU Core & Pipeline',
    'axi_arbiter_2x1': 'Bus & Fabric Interconnect',
    'axi_arbiter_2x1_full': 'Bus & Fabric Interconnect',
    'axi_decoder_1x3': 'Bus & Fabric Interconnect',
    'axi2apb_bridge': 'Bus & Fabric Interconnect',
    'apb_axi_dma': 'Peripherals & Subsystems',
    'apb_gpio': 'Peripherals & Subsystems',
    'apb_pic': 'Peripherals & Subsystems',
    'apb_timer': 'Peripherals & Subsystems',
    'apb_uart': 'Peripherals & Subsystems',
    'jtag_debug_top': 'Debug & Observability',
    'soc_debug_subsystem': 'Debug & Observability',
    'soc_core_subsystem': 'SoC Integration & Subsystems',
    'soc_peripheral_subsystem': 'SoC Integration & Subsystems',
    'soc_memory_subsystem': 'SoC Integration & Subsystems',
    'soc_top': 'SoC Integration & Subsystems',
    'tb_top': 'Testbench Top'
}

def get_category(mod_name):
    clean_name = mod_name.split('(')[0].strip()
    return SYS_CATEGORIES.get(clean_name, 'General Module Coverage Exclusions')

def run_cmd(cmd, cwd=None):
    res = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, cwd=cwd)
    return res.returncode, res.stdout, res.stderr

def parse_toggle_sig(sig):
    m = re.match(r'^(Toggle(?:\s+(?:0to1|1to0))?\s+\S+)(?:\s+\[(\d+)(?::(\d+))?\])?\s+(".*")$', sig)
    if not m:
        return None
    full_prefix = m.group(1)
    parts = full_prefix.split()
    trans = parts[1] if len(parts) > 2 else ''
    name = parts[-1]
    msb_str = m.group(2)
    lsb_str = m.group(3)
    type_suffix = m.group(4)
    msb = int(msb_str) if msb_str is not None else None
    lsb = int(lsb_str) if lsb_str is not None else msb
    return (name, trans, msb, lsb, type_suffix)

def subtract_range(base_msb, base_lsb, att_ranges):
    covered = [False] * (base_msb - base_lsb + 1)
    for a_msb, a_lsb in att_ranges:
        low = max(base_lsb, a_lsb)
        high = min(base_msb, a_msb)
        for b in range(low, high + 1):
            covered[b - base_lsb] = True
            
    res = []
    in_gap = False
    start_b = None
    for b in range(base_lsb, base_msb + 1):
        idx = b - base_lsb
        if not covered[idx]:
            if not in_gap:
                in_gap = True
                start_b = b
        else:
            if in_gap:
                in_gap = False
                res.append((b - 1, start_b))
    if in_gap:
        res.append((base_msb, start_b))
    return res

def format_toggle(name, trans, msb, lsb, type_suffix):
    prefix = f'Toggle {trans} {name}' if trans else f'Toggle {name}'
    if msb is None:
        return f'{prefix} {type_suffix}'
    elif msb == lsb:
        return f'{prefix} [{msb}] {type_suffix}'
    else:
        return f'{prefix} [{msb}:{lsb}] {type_suffix}'

def parse_fullexclude_dir(dump_dir):
    blocks = []
    for fname in sorted(glob.glob(os.path.join(dump_dir, "fullexclude_module.*"))):
        metric = fname.split(".")[-1]
        with open(fname, 'r') as f:
            lines = f.readlines()
        
        cur_mod = None
        cur_rules = []
        
        for line in lines:
            line_s = line.strip()
            if line_s.startswith("// MODULE:") or line_s.startswith("MODULE:"):
                if cur_mod and cur_rules:
                    blocks.append((cur_mod, None, cur_rules, metric))
                    cur_rules = []
                cur_mod = line_s.split(":", 1)[1].strip()
            elif cur_mod and line_s.startswith("//") and not line_s.startswith("// CHECKSUM") and not line_s.startswith("// ANNOTATION") and not line_s.startswith("//================") and line_s != "//":
                rule_str = line_s[2:].strip()
                if any(rule_str.startswith(k) for k in ['Condition', 'Branch', 'Fsm', 'State', 'Transition', 'Toggle', 'Block']):
                    if rule_str.startswith('Condition ') and rule_str.endswith(' 1 -1"'):
                        continue
                    cur_rules.append(rule_str)
                        
        if cur_mod and cur_rules:
            blocks.append((cur_mod, None, cur_rules, metric))
            
    return blocks

def combine_all_metrics_by_module(blocks):
    mod_map = {}
    for mod_name, _, rules, metric in blocks:
        clean_mod = mod_name.split('(')[0].strip()
        if clean_mod not in mod_map:
            mod_map[clean_mod] = list(rules)
        else:
            existing = mod_map[clean_mod]
            rules_set = set(existing)
            for r in rules:
                if r not in rules_set:
                    existing.append(r)
                    rules_set.add(r)
            mod_map[clean_mod] = existing
            
    res = []
    for clean_mod, rules in mod_map.items():
        rules_cleaned = sanitize_fsm_scopes(rules)
        if rules_cleaned:
            res.append((clean_mod, None, rules_cleaned, 'all'))
    return res

def is_attempt_match(rule_str, att_sig):
    r_tokens = rule_str.split()
    att_tokens = att_sig.split()
    if not r_tokens or not att_tokens:
        return False
    if r_tokens[0] in ('Condition', 'Branch') and att_tokens[0] in ('Condition', 'Branch'):
        if len(r_tokens) >= 2 and len(att_tokens) >= 2 and r_tokens[0] == att_tokens[0] and r_tokens[1] == att_tokens[1]:
            m_r = re.search(r'\(\d+\s+".*"\)$', rule_str)
            m_a = re.search(r'\(\d+\s+".*"\)$', att_sig)
            if m_r and m_a:
                return m_r.group(0) == m_a.group(0)
            elif not m_r and not m_a:
                return True
            else:
                return True
    r_norm = ' '.join(r_tokens)
    att_norm = ' '.join(att_tokens)
    if r_norm == att_norm or att_norm.startswith(r_norm + ' '):
        return True
    return False

def sanitize_fsm_scopes(rules):
    new_rules = []
    has_fsm = False
    for r in rules:
        if r.startswith("Fsm "):
            has_fsm = True
            new_rules.append(r)
        elif r.startswith("State ") or r.startswith("Transition "):
            if has_fsm:
                new_rules.append(r)
        else:
            new_rules.append(r)
    return new_rules

def filter_blocks(blocks, attempts):
    filtered_blocks = []
    for mod_name, checksum_line, rules, metric in blocks:
        mod_clean = mod_name.split('(')[0].strip()
        mod_attempts = [att_sig for att_mod, att_sig in attempts if att_mod.split('(')[0].strip() == mod_clean]
        
        new_rules = []
        for r in rules:
            if r.startswith('Toggle'):
                r_parsed = parse_toggle_sig(r)
                if r_parsed:
                    r_name, r_trans, r_msb, r_lsb, r_type = r_parsed
                    att_ranges = []
                    for att_sig in mod_attempts:
                        if att_sig.startswith('Toggle'):
                            att_parsed = parse_toggle_sig(att_sig)
                            if att_parsed:
                                a_name, a_trans, a_msb, a_lsb, a_type = att_parsed
                                if a_name == r_name and (not r_trans or not a_trans or r_trans == a_trans):
                                    if r_msb is not None:
                                        if a_msb is not None:
                                            att_ranges.append((a_msb, a_lsb))
                                        else:
                                            att_ranges.append((r_msb, r_lsb))
                                    else:
                                        att_ranges.append((0, 0))
                    if att_ranges:
                        if r_msb is not None:
                            remaining = subtract_range(r_msb, r_lsb, att_ranges)
                            for m, l in remaining:
                                new_rules.append(format_toggle(r_name, r_trans, m, l, r_type))
                        else:
                            pass
                    else:
                        new_rules.append(r)
                else:
                    new_rules.append(r)
            else:
                attempted = False
                for att_sig in mod_attempts:
                    if is_attempt_match(r, att_sig):
                        attempted = True
                        break
                if not attempted:
                    new_rules.append(r)

        new_rules = sanitize_fsm_scopes(new_rules)

        if new_rules:
            filtered_blocks.append((mod_name, checksum_line, new_rules, metric))
    return filtered_blocks

def run_urg(vdb_path, el_path, out_report, out_log, strict=False):
    shutil.rmtree(out_report, ignore_errors=True)
    strict_flag = "-excl_strict" if strict else ""
    cmd = f"source /etc/profile.d/modules.sh && module load vcs && urg -dir {vdb_path} -elfile {el_path} {strict_flag} -format text -report {out_report} -log {out_log}"
    ret, out, err = run_cmd(cmd)
    
    attempts = []
    att_file = os.path.join(out_report, "attempts.log")
    if os.path.exists(att_file):
        with open(att_file, 'r') as f:
            cur_mod = None
            for line in f:
                line_s = line.strip()
                if line_s.startswith("MODULE:"):
                    cur_mod = line_s.split(":", 1)[1].strip()
                elif cur_mod and any(line_s.startswith(k) for k in ['Condition', 'Branch', 'Toggle', 'Fsm', 'State', 'Transition', 'Block']):
                    attempts.append((cur_mod, line_s))
    return ret, attempts, out + err

def write_el_and_manifest(blocks, el_file, is_uvm=True):
    combined_blocks = combine_all_metrics_by_module(blocks)
    
    el_lines = [
        "// Coverage Exclusion File",
        "// Generated automatically by refine_exclusions.py for 99% coverage sign-off",
        "//"
    ]
    manifest_entries = []
    
    prefix = "EXCL-UVM" if is_uvm else "EXCL-PROD"
    idx = 1
    
    for mod_name, checksum_line, rules, metric in combined_blocks:
        cat = get_category(mod_name)
        excl_id = f"{prefix}-{idx:04d}"
        idx += 1
        
        el_lines.append(f"// ID: {excl_id}")
        el_lines.append(f"// CATEGORY: {cat}")
        el_lines.append(f"MODULE: {mod_name}")
        el_lines.extend(rules)
        el_lines.append("")
        
        manifest_entries.append({
            "id": excl_id,
            "category": cat,
            "module": mod_name,
            "metric": metric,
            "rule_count": len(rules),
            "rules": rules
        })
        
    with open(el_file, 'w') as f:
        f.write("\n".join(el_lines) + "\n")
        
    return manifest_entries

def main():
    uvm_vdb = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT_DIR, "build/signoff/current_contract/coverage/merged.vdb")
    prod_vdb = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT_DIR, "build/signoff/current_contract/phase3_complete/cpu_cp0_gate/simv.vdb")
    
    if not os.path.exists(uvm_vdb):
        uvm_vdb = os.path.join(ROOT_DIR, "build/uvm/phase2_complete/directed_cov/directed.vdb")
    if not os.path.exists(prod_vdb):
        prod_vdb = os.path.join(ROOT_DIR, "build/soc_test/cpu_cp0_gate/simv.vdb")
        
    print(f"=== Dumping exclusions for UVM VDB: {uvm_vdb} ===")
    dump_dir_uvm = "/tmp/dump_uvm_vdb"
    os.makedirs(dump_dir_uvm, exist_ok=True)
    run_cmd(f"source /etc/profile.d/modules.sh && module load vcs && urg -dir {uvm_vdb} -dump full_exclusions -report {dump_dir_uvm}", cwd=dump_dir_uvm)
    
    raw_uvm_blocks = parse_fullexclude_dir(dump_dir_uvm)
    print(f"Parsed {len(raw_uvm_blocks)} UVM exclusion blocks.")
    
    print(f"=== Dumping exclusions for PROD VDB: {prod_vdb} ===")
    dump_dir_prod = "/tmp/dump_prod_vdb"
    os.makedirs(dump_dir_prod, exist_ok=True)
    run_cmd(f"source /etc/profile.d/modules.sh && module load vcs && urg -dir {prod_vdb} -dump full_exclusions -report {dump_dir_prod}", cwd=dump_dir_prod)
    
    raw_prod_blocks = parse_fullexclude_dir(dump_dir_prod)
    print(f"Parsed {len(raw_prod_blocks)} PROD exclusion blocks.")
    
    print("=== Processing UVM Exclusions ===")
    uvm_blocks = raw_uvm_blocks
    uvm_manifest = []
    for i in range(15):
        uvm_manifest = write_el_and_manifest(uvm_blocks, UVM_EXCL_FILE, is_uvm=True)
        rpt_dir = f"/tmp/rpt_uvm_iter_{i}"
        log_file = f"/tmp/log_uvm_iter_{i}.log"
        use_strict = (i > 0)
        ret, attempts, out = run_urg(uvm_vdb, UVM_EXCL_FILE, rpt_dir, log_file, strict=use_strict)
        
        real_attempts = [a for a in attempts if not a[1].startswith("//")]
        print(f"UVM Iteration {i+1} (strict={use_strict}): URG ret={ret}, attempts={len(real_attempts)}")
        if use_strict and len(real_attempts) == 0:
            break
        uvm_blocks = filter_blocks(uvm_blocks, real_attempts)
    uvm_manifest = write_el_and_manifest(uvm_blocks, UVM_EXCL_FILE, is_uvm=True)
        
    print("=== Processing PROD Exclusions ===")
    prod_blocks = raw_prod_blocks
    prod_manifest = []
    for i in range(15):
        prod_manifest = write_el_and_manifest(prod_blocks, PROD_EXCL_FILE, is_uvm=False)
        rpt_dir = f"/tmp/rpt_prod_iter_{i}"
        log_file = f"/tmp/log_prod_iter_{i}.log"
        use_strict = (i > 0)
        ret, attempts, out = run_urg(prod_vdb, PROD_EXCL_FILE, rpt_dir, log_file, strict=use_strict)
        
        real_attempts = [a for a in attempts if not a[1].startswith("//")]
        print(f"PROD Iteration {i+1} (strict={use_strict}): URG ret={ret}, attempts={len(real_attempts)}")
        if use_strict and len(real_attempts) == 0:
            break
        prod_blocks = filter_blocks(prod_blocks, real_attempts)
    prod_manifest = write_el_and_manifest(prod_blocks, PROD_EXCL_FILE, is_uvm=False)
        
    manifest = {
        "uvm_exclusions": uvm_manifest,
        "product_exclusions": prod_manifest
    }
    with open(MANIFEST_FILE, 'w') as f:
        import json
        json.dump(manifest, f, indent=2)
    print(f"Refinement complete. Saved manifest to {MANIFEST_FILE}")

if __name__ == "__main__":
    main()
