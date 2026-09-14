# Builds the C core, the headless CLI and the kernel tests with the host
# compiler. On an arm64 host (Apple silicon, aarch64 Linux, or qemu-user)
# the NEON kernels are compiled in and tested against the portable path.
#
#   make            build/smfb-cli and build/kernel_test
#   make test       run the kernel tests
#   make run        run the CLI for 20 simulated seconds
#   make BUILD=build-arm64 CC=aarch64-linux-gnu-gcc \
#        RUN="qemu-aarch64 -L /usr/aarch64-linux-gnu" test        cross + emulate

CC      ?= cc
RUN     ?=
CFLAGS  ?= -O2 -std=c11 -Wall -Wextra -Wno-unused-parameter -ffp-contract=off
CORE    := SMFBKit/Sources/SMFBCore
SRCS    := $(CORE)/connectome.c $(CORE)/brain.c $(CORE)/world.c $(CORE)/dispatch.c $(CORE)/lif_portable.c $(CORE)/lif_neon.S
INC     := -I$(CORE)/include
BUILD   ?= build

all: $(BUILD)/smfb-cli $(BUILD)/kernel_test

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/smfb-cli: $(SRCS) tools/smfb_cli.c $(CORE)/include/smfb_core.h | $(BUILD)
	$(CC) $(CFLAGS) $(INC) $(SRCS) tools/smfb_cli.c -lm -o $@

$(BUILD)/kernel_test: $(SRCS) tools/kernel_test.c $(CORE)/include/smfb_core.h | $(BUILD)
	$(CC) $(CFLAGS) $(INC) $(SRCS) tools/kernel_test.c -lm -o $@

test: $(BUILD)/kernel_test
	$(RUN) $(BUILD)/kernel_test

run: $(BUILD)/smfb-cli
	$(RUN) $(BUILD)/smfb-cli 1 20

clean:
	rm -rf $(BUILD)

.PHONY: all test run clean
