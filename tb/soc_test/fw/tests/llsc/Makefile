TEST_NAME    := llsc
TEST_SOURCES := main.c
FW_TOP_DIR   := ../..
include $(FW_TOP_DIR)/common/Makefile.rules

ifeq ($(COHERENCY),1)
CFLAGS += -DLL_SC_COHERENCY
endif
