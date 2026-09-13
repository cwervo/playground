# isolates - GNU make build
#
#   make            build bin/isolates
#   make test       unit tests + HTTP smoke test
#   make run        serve the sample workers on :8787
#   make bench      throughput of the sample counter worker
#   make dashboard  build the Flutter web dashboard (needs flutter)
#   make clean

CC      ?= cc
ARCH    := $(shell uname -m)
CFLAGS  ?= -O2 -g
CFLAGS  += -std=c11 -Wall -Wextra -Wpedantic -Wshadow -Wno-unused-parameter \
           -D_GNU_SOURCE -Iruntime/include
LDFLAGS ?=
LDLIBS  := -lm

ifeq ($(ARCH),x86_64)
  CTX_SRC := runtime/src/context_x86_64.S
else ifeq ($(ARCH),aarch64)
  CTX_SRC := runtime/src/context_aarch64.S
else ifeq ($(ARCH),arm64)
  CTX_SRC := runtime/src/context_aarch64.S
else
  $(error unsupported architecture '$(ARCH)': need x86_64 or aarch64)
endif

SRCS     := $(wildcard runtime/src/*.c)
OBJS     := $(patsubst runtime/src/%.c,build/%.o,$(SRCS)) build/context_asm.o
LIB_OBJS := $(filter-out build/main.o,$(OBJS))
HDR      := runtime/include/isolates.h

PORT ?= 8787

.PHONY: all test run bench dashboard clean asm-listing

all: bin/isolates

bin/isolates: $(OBJS) | bin
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(OBJS) $(LDLIBS)

bin/test_vm: tests/test_vm.c $(LIB_OBJS) | bin
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ tests/test_vm.c $(LIB_OBJS) $(LDLIBS)

build/%.o: runtime/src/%.c $(HDR) | build
	$(CC) $(CFLAGS) -c -o $@ $<

build/context_asm.o: $(CTX_SRC) | build
	$(CC) $(CFLAGS) -c -o $@ $<

build bin:
	mkdir -p $@

test: bin/isolates bin/test_vm
	./bin/test_vm
	sh tests/smoke.sh ./bin/isolates

run: bin/isolates
	./bin/isolates serve --port $(PORT) --examples workers \
	  $(foreach w,$(wildcard workers/*.isoasm),--load $(w)) \
	  $(if $(wildcard dashboard/build/web/index.html),--dashboard dashboard/build/web,) -v

bench: bin/isolates
	./bin/isolates bench workers/counter.isoasm -n 20000 -c 128

asm-listing: build/context_asm.o
	objdump -d build/context_asm.o

dashboard:
	cd dashboard && flutter pub get && flutter build web --release

clean:
	rm -rf build bin
