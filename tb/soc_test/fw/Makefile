# =============================================================================
# tb/soc_test/fw/Makefile — multi-firmware build orchestrator.
#
# Each subdirectory under tests/ is a self-contained firmware. Common assets
# (boot.s, link.ld, print/excpt helpers, address defines) live in common/.
#
# Usage (backward-compatible with the pre-split single-firmware layout):
#   make                       # builds soc_smoke (default), out to OUT_DIR
#   make FW_NAME=isa_r2_sweep  # builds a specific test firmware
#   make all-firmwares         # builds every test under tests/
#
# The top-level Makefile in the repo root still invokes:
#   $(MAKE) -C tb/soc_test/fw OUT_DIR=<dir> FW_BASE=firmware all
# which forwards to the default test's Makefile.
# =============================================================================

FW_NAME ?= soc_smoke
OUT_DIR ?= .
FW_BASE ?= firmware

TEST_DIRS := $(wildcard tests/*)

.PHONY: all all-firmwares clean

all:
	$(MAKE) -C tests/$(FW_NAME) OUT_DIR=$(abspath $(OUT_DIR)) FW_BASE=$(FW_BASE)

all-firmwares:
	@for d in $(TEST_DIRS); do \
		name=$$(basename $$d); \
		if [ -f $$d/Makefile ]; then \
			echo "==> building firmware: $$name"; \
			$(MAKE) -C $$d OUT_DIR=$(abspath $(OUT_DIR))/$$name FW_BASE=firmware || exit 1; \
		else \
			echo "==> skipping non-firmware test asset: $$name"; \
		fi; \
	done

clean:
	@for d in $(TEST_DIRS); do \
		if [ -f $$d/Makefile ]; then $(MAKE) -C $$d clean; fi; \
	done
