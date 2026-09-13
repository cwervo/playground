#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#───vi: set et ft=make ts=8 tw=8 fenc=utf-8 :vi───────────────────────┘
#
# minibrowser — assembly instructions
#
# This Makefile follows the redbean / cosmopolitan conventions: it is
# GNU make only (gmake on the BSDs), it puts every output under o/, and
# a single portable C file is the whole native engine.
#
#   make                  build the engine CLI and shared library for this OS
#   make check            run the engine over the fixture pages (no network)
#   make ape              build o/minibrowser.com, an Actually Portable
#                         Executable, with cosmocc (downloaded on demand)
#   make app              build the Flutter desktop app for this OS and
#                         bundle the engine library next to it
#   make test             engine checks + Flutter widget/render tests
#   make test-live        render the live google/facebook/apple/wikipedia
#                         home pages (needs network + TLS=openssl)
#   make run              launch the Flutter app
#   make fixtures         re-capture fixtures/*.html from the live sites
#   make clean
#
# Variables you can override on the command line:
#
#   CC=clang              C compiler (default: cc)
#   TLS=openssl|none      link the CLI against OpenSSL for https:// (default:
#                         auto-detected with pkg-config)
#   FLUTTER=flutter       path to the flutter tool
#   COSMOCC=...           path to a cosmocc toolchain directory

SHELL := /bin/sh
.SUFFIXES:
.DELETE_ON_ERROR:
MAKEFLAGS += --no-builtin-rules

CC      ?= cc
FLUTTER ?= flutter
TLS     ?= auto
COSMOCC_VERSION ?= 4.0.2
COSMOCC ?= .cosmocc/$(COSMOCC_VERSION)

# ---------------------------------------------------------------- host os

ifeq ($(OS),Windows_NT)
  HOST := windows
else
  UNAME_S := $(shell uname -s 2>/dev/null)
  ifeq ($(UNAME_S),Darwin)
    HOST := macos
  else ifeq ($(UNAME_S),Linux)
    HOST := linux
  else ifneq (,$(findstring BSD,$(UNAME_S)))
    HOST := bsd
  else
    HOST := unknown
  endif
endif

UNAME_M := $(shell uname -m 2>/dev/null || echo x64)
ifneq (,$(filter x86_64 amd64 AMD64,$(UNAME_M)))
  ARCH := x64
else ifneq (,$(filter arm64 aarch64,$(UNAME_M)))
  ARCH := arm64
else
  ARCH := $(UNAME_M)
endif

ifeq ($(HOST),windows)
  EXE      := .exe
  DLL      := dll
  SHFLAGS  := -shared
  LIBS     := -lws2_32
  SOPREFIX :=
else ifeq ($(HOST),macos)
  EXE      :=
  DLL      := dylib
  SHFLAGS  := -dynamiclib -install_name @rpath/libminibrowser.dylib
  LIBS     :=
  SOPREFIX := lib
else
  EXE      :=
  DLL      := so
  SHFLAGS  := -shared
  LIBS     :=
  SOPREFIX := lib
endif

# ---------------------------------------------------------------- flags

CFLAGS  ?= -O2 -g
CFLAGS  += -std=c11 -Wall -Wextra -Wshadow -fPIC
CPPFLAGS +=
LDFLAGS +=

ifeq ($(TLS),auto)
  ifeq ($(shell pkg-config --exists openssl 2>/dev/null && echo yes),yes)
    TLS := openssl
  else ifeq ($(HOST),macos)
    # Homebrew keeps OpenSSL out of the default paths
    ifneq (,$(wildcard /opt/homebrew/opt/openssl/include/openssl/ssl.h))
      TLS := openssl
      CPPFLAGS += -I/opt/homebrew/opt/openssl/include
      LDFLAGS  += -L/opt/homebrew/opt/openssl/lib
    else
      TLS := none
    endif
  else
    TLS := none
  endif
endif

ifeq ($(TLS),openssl)
  TLS_CPPFLAGS := -DMB_TLS_OPENSSL $(shell pkg-config --cflags openssl 2>/dev/null)
  TLS_LIBS     := $(shell pkg-config --libs openssl 2>/dev/null || echo -lssl -lcrypto)
else
  TLS_CPPFLAGS :=
  TLS_LIBS     :=
endif

# ---------------------------------------------------------------- outputs

O        := o
OUT      := $(O)/$(HOST)-$(ARCH)
ENGINE   := engine/minibrowser.c
CLI      := $(OUT)/minibrowser$(EXE)
LIB      := $(OUT)/$(SOPREFIX)minibrowser.$(DLL)
APE      := $(O)/minibrowser.com
FIXTURES := fixtures/google.html fixtures/facebook.html fixtures/apple.html fixtures/wikipedia.html
SITES    := https://www.google.com/ https://www.facebook.com/ https://www.apple.com/ https://en.wikipedia.org/wiki/Main_Page

.PHONY: all engine lib cli check test test-live app run fixtures ape clean help

all: cli lib

engine: cli lib
cli: $(CLI)
lib: $(LIB)

$(OUT):
	mkdir -p $(OUT)

$(CLI): $(ENGINE) | $(OUT)
	$(CC) $(CPPFLAGS) $(TLS_CPPFLAGS) $(CFLAGS) -o $@ $< $(LDFLAGS) $(TLS_LIBS) $(LIBS)

# The shared library is what the Flutter shell loads through dart:ffi. It
# never links TLS: the Dart side fetches pages with its own HTTP client, the
# native side only parses, styles and lays out.
$(LIB): $(ENGINE) | $(OUT)
	$(CC) $(CPPFLAGS) $(CFLAGS) -DMB_NO_MAIN $(SHFLAGS) -o $@ $< $(LDFLAGS) $(LIBS)

# ---------------------------------------------------------------- ape

# Downloads the cosmocc toolchain the same way cosmopolitan's own build
# does, then compiles the engine into one binary that runs on Linux, macOS,
# Windows, FreeBSD, OpenBSD and NetBSD on both x86-64 and arm64.
$(COSMOCC)/bin/cosmocc:
	build/download-cosmocc.sh $(COSMOCC) $(COSMOCC_VERSION)

ape: $(APE)

$(APE): $(ENGINE) $(COSMOCC)/bin/cosmocc
	mkdir -p $(O)
	$(COSMOCC)/bin/cosmocc -O2 -std=c11 -Wall -o $@ $<

# ---------------------------------------------------------------- tests

check: $(CLI)
	@sh test/check-engine.sh $(CLI)

test: check app-test

app-test: $(LIB)
	cd app && MINIBROWSER_ENGINE=$(abspath $(LIB)) $(FLUTTER) test

# Renders the real home pages through the C engine. Needs network access
# and an https-capable CLI (TLS=openssl, the default when OpenSSL is found).
test-live: $(CLI)
	@sh test/check-live.sh $(CLI) $(SITES)

# ---------------------------------------------------------------- flutter

APPDIR := app
ifeq ($(HOST),linux)
  BUNDLE := $(APPDIR)/build/linux/$(ARCH)/release/bundle
  FLUTTER_PLATFORM := linux
else ifeq ($(HOST),macos)
  BUNDLE := $(APPDIR)/build/macos/Build/Products/Release/minibrowser.app/Contents/Frameworks
  FLUTTER_PLATFORM := macos
else ifeq ($(HOST),windows)
  BUNDLE := $(APPDIR)/build/windows/$(ARCH)/runner/Release
  FLUTTER_PLATFORM := windows
else
  BUNDLE := $(APPDIR)/build/$(HOST)
  FLUTTER_PLATFORM := $(HOST)
endif

app: $(LIB)
	cd $(APPDIR) && $(FLUTTER) pub get
	cd $(APPDIR) && $(FLUTTER) build $(FLUTTER_PLATFORM) --release
	mkdir -p $(BUNDLE)/lib
	cp $(LIB) $(BUNDLE)/lib/
	@echo "built $(BUNDLE)"

run: $(LIB)
	cd $(APPDIR) && MINIBROWSER_ENGINE=$(abspath $(LIB)) $(FLUTTER) run -d $(FLUTTER_PLATFORM)

# ---------------------------------------------------------------- fixtures

# Re-captures the four home pages. The checked-in fixtures are offline
# stand-ins written to mirror each page's structure; run this when you have
# network access to test against the real markup.
fixtures:
	@for s in $(SITES); do \
	  n=$$(echo $$s | sed -e 's|https://www\.||' -e 's|https://en\.||' -e 's|\..*||'); \
	  echo "fetching $$s -> fixtures/$$n.html"; \
	  curl -fsSL -A "Mozilla/5.0 (compatible; minibrowser/0.1)" -o fixtures/$$n.html "$$s" || exit 1; \
	done

# ---------------------------------------------------------------- misc

clean:
	rm -rf $(O)
	rm -rf $(APPDIR)/build

help:
	@sed -n '4,40p' Makefile | sed 's/^# \{0,1\}//'
