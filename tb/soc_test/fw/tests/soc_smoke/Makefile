# soc_smoke — legacy monolithic firmware, layout-preserved vs pre-split baseline.
# Does NOT link common/print.c or common/excpt.c; its own inline helpers keep
# the code layout / CPU boot timing identical to what signoff #12 validated.
TEST_NAME         := soc_smoke
TEST_SOURCES      := main.c
FW_TOP_DIR        := ../..
LEGACY_MONOLITHIC := 1
include $(FW_TOP_DIR)/common/Makefile.rules
