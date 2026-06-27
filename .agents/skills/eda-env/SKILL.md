---
name: eda-env
description: Loading EDA tool environments (VCS, Verdi, Virtuoso) using environment modules.
---

# Loading EDA Tool Environments

When working in this workspace, EDA tools (such as VCS, Verdi, and Virtuoso) must be loaded using the `module` command.

## Initialization
In any non-interactive shell or script, initialize the `module` command environment by sourcing:
```bash
source /etc/profile.d/modules.sh
```

## Available Modules
- `vcs` (Synopsys VCS)
- `verdi` (Synopsys Verdi)
- `ic231` (Cadence Virtuoso IC 23.1)

## Standard Usage in Scripts
```bash
source /etc/profile.d/modules.sh
module load vcs verdi ic231
```
