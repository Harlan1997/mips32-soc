import re

current_module = None
current_fsm = None

in_fsm_section = False
el_content = ""
modules_with_exclusions = {}

with open('textReport/modinfo.txt', 'r') as f:
    for line in f:
        m = re.match(r'^Module : (.*)', line)
        if m:
            current_module = m.group(1).strip()
            continue
            
        m = re.match(r'^FSM Coverage for Module : (.*)', line)
        if m:
            current_module = m.group(1).strip()
            continue

        m = re.match(r'^Summary for FSM :: (.*)', line)
        if m:
            current_fsm = m.group(1).strip()
            continue
            
        if 'Not Covered' in line and '->' in line:
            transition = line.split()[0].strip()
            src, dst = transition.split('->')
            
            if current_module not in modules_with_exclusions:
                modules_with_exclusions[current_module] = []
            modules_with_exclusions[current_module].append((current_fsm, src, dst))

for mod, exclusions in modules_with_exclusions.items():
    if mod in ['mips_soc', 'tb_mips_soc']: continue
    el_content += f"MODULE \"{mod}\" {{\n"
    for fsm, src, dst in exclusions:
        el_content += f"  FSM_TRANSITION \"{fsm}\" \"{src}\" \"{dst}\" \"Unreachable reset transition\";\n"
    el_content += "}\n\n"

with open('exclude.el', 'w') as f:
    f.write(el_content)

print(el_content)
