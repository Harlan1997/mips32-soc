#!/usr/bin/env python3
"""
Automated Exclusion Audit Script for MIPS32 SoC
Verifies:
1. Unique IDs across manifest and .el files.
2. Permitted Categories (UNREACHABLE_CURRENT_CONTRACT, DEFENSIVE_ILLEGAL_STATE,
   STATIC_TIEOFF_RESERVED, NON_PRODUCT_VERIFICATION, UNINSTANTIATED_CONFIGURATION, OUT_OF_SCOPE_FEATURE).
3. Traceability (non-empty rationale and evidence for every ID).
4. Sync Check between manifest.json and .el rule blocks.
"""

import os
import sys
import json
import re

PERMITTED_CATEGORIES = {
    'UNREACHABLE_CURRENT_CONTRACT',
    'DEFENSIVE_ILLEGAL_STATE',
    'STATIC_TIEOFF_RESERVED',
    'NON_PRODUCT_VERIFICATION',
    'UNINSTANTIATED_CONFIGURATION',
    'OUT_OF_SCOPE_FEATURE'
}

def audit_exclusions(project_root):
    manifest_path = os.path.join(project_root, 'tb/coverage/manifest.json')
    uvm_el_path = os.path.join(project_root, 'tb/coverage/uvm_exclusions.el')
    prod_el_path = os.path.join(project_root, 'tb/coverage/product_exclusions.el')
    
    errors = []
    
    if not os.path.exists(manifest_path):
        errors.append(f"Missing manifest file: {manifest_path}")
    if not os.path.exists(uvm_el_path):
        errors.append(f"Missing UVM exclusion file: {uvm_el_path}")
    if not os.path.exists(prod_el_path):
        errors.append(f"Missing product exclusion file: {prod_el_path}")
        
    if errors:
        for err in errors:
            print(f"AUDIT ERROR: {err}", file=sys.stderr)
        return False
        
    with open(manifest_path, 'r') as f:
        try:
            manifest = json.load(f)
        except Exception as e:
            print(f"AUDIT ERROR: Malformed manifest.json: {e}", file=sys.stderr)
            return False
            
    seen_ids = set()
    manifest_ids = set()
    
    for entry_id, data in manifest.items():
        if entry_id in seen_ids:
            errors.append(f"Duplicate ID in manifest.json: {entry_id}")
        seen_ids.add(entry_id)
        manifest_ids.add(entry_id)
        
        # Check required fields
        if data.get('id') != entry_id:
            errors.append(f"ID mismatch in entry {entry_id}: data.id={data.get('id')}")
            
        cat = data.get('category')
        if cat not in PERMITTED_CATEGORIES:
            errors.append(f"Invalid category '{cat}' in manifest entry {entry_id}. Permitted: {PERMITTED_CATEGORIES}")
            
        rationale = data.get('rationale', '').strip()
        if not rationale:
            errors.append(f"Empty rationale in manifest entry {entry_id}")
            
        evidence = data.get('evidence', '').strip()
        if not evidence:
            errors.append(f"Empty evidence in manifest entry {entry_id}")
            
    # Function to parse IDs from .el file
    def parse_el_ids(filepath, domain):
        with open(filepath, 'r') as f:
            lines = f.readlines()
        el_ids = []
        for line in lines:
            line_str = line.strip()
            if line_str.startswith("// ID:"):
                m = re.search(r'// ID:\s*([A-Za-z0-9_-]+)', line_str)
                if m:
                    el_id = m.group(1)
                    el_ids.append(el_id)
        return el_ids

    uvm_el_ids = parse_el_ids(uvm_el_path, 'uvm')
    prod_el_ids = parse_el_ids(prod_el_path, 'prod')
    
    all_el_ids = uvm_el_ids + prod_el_ids
    seen_el_ids = set()
    for el_id in all_el_ids:
        if el_id in seen_el_ids:
            errors.append(f"Duplicate ID in .el files: {el_id}")
        seen_el_ids.add(el_id)
        
    # Check sync between manifest and .el files
    missing_in_el = manifest_ids - seen_el_ids
    if missing_in_el:
        errors.append(f"IDs in manifest.json missing from .el files: {sorted(list(missing_in_el))[:10]}")
        
    missing_in_manifest = seen_el_ids - manifest_ids
    if missing_in_manifest:
        errors.append(f"IDs in .el files missing from manifest.json: {sorted(list(missing_in_manifest))[:10]}")
        
    if errors:
        print("======================================================================", file=sys.stderr)
        print(" EXCLUSION AUDIT FAILED WITH ERRORS:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        print("======================================================================", file=sys.stderr)
        return False
        
    print("======================================================================")
    print(" EXCLUSION AUDIT PASSED SUCCESSFULLY!")
    print(f" Total audited rules: {len(manifest_ids)} entries across manifest & .el files.")
    print("======================================================================")
    return True

if __name__ == '__main__':
    root = os.path.realpath(os.path.join(os.path.dirname(__file__), '../..'))
    success = audit_exclusions(root)
    sys.exit(0 if success else 1)
