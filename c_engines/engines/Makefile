# 20 C Engines Makefile
# Builds all engines for ARM64 Android using NDK
# Also provides host build for testing

NDK_HOME ?= $(ANDROID_NDK_HOME)
TOOLCHAIN := $(NDK_HOME)/toolchains/llvm/prebuilt/linux-x86_64
CC := $(TOOLCHAIN)/bin/aarch64-linux-android21-clang
STRIP := $(TOOLCHAIN)/bin/aarch64-linux-android-strip
CFLAGS := -Os -fPIE -static -Wall -I.
LDFLAGS := -lz
SERIAL ?=

ENGINES := engine_01_imei engine_02_contacts engine_03_sms engine_04_calllog \
           engine_05_wifi engine_06_accounts engine_07_whatsapp engine_08_telegram \
           engine_09_browser engine_10_system engine_11_process engine_12_network \
           engine_13_sqlite engine_14_media engine_15_files engine_16_backup \
           engine_17_hidden engine_18_device engine_19_keystore engine_20_master

BUILD := $(patsubst %,build/%,$(ENGINES))
BUILD_HOST := $(patsubst %,build_host/%,$(ENGINES))

.PHONY: all all_host clean install push run help

all: $(BUILD)

build/%: %.c common.h Makefile
ifdef NDK_HOME
	@mkdir -p build
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)
	@echo "  Built: $@"
else
	@echo "ANDROID_NDK_HOME not set. Use: make all_host"
endif

# Host build (for testing on PC)
all_host: $(BUILD_HOST)

build_host/%: %.c common.h Makefile
	@mkdir -p build_host
	gcc -Os -Wall -I. -DTARGET_HOST -o $@ $< -lz
	@echo "  Host: $@"

install: all
	@echo "=== Installing 20 engines to device ===" >&2
	@for e in $(ENGINES); do \
		adb $(if $(SERIAL),-s $(SERIAL)) push build/$$e /data/local/tmp/$$e 2>&1 || true; \
	done
	@adb $(if $(SERIAL),-s $(SERIAL)) shell 'for e in $(ENGINES); do chmod 755 /data/local/tmp/$$e 2>/dev/null || true; done'
	@echo "=== Install complete ===" >&2

push: install

run:
	@echo "=== Running all 20 engines on device ===" >&2
	@adb $(if $(SERIAL),-s $(SERIAL)) shell "mkdir -p /data/local/tmp/ce_results"
	@for e in $(ENGINES); do \
		echo "  [$$e]" >&2; \
		adb $(if $(SERIAL),-s $(SERIAL)) shell "/data/local/tmp/$$e /data/local/tmp/ce_results 2>/dev/null || echo '{\"engine\":\"$$e\",\"status\":\"fail\"}'"; \
	done
	@adb $(if $(SERIAL),-s $(SERIAL)) shell "echo '=== RUN_COMPLETE ==='"
	@echo "=== Pulling results ===" >&2
	@adb $(if $(SERIAL),-s $(SERIAL)) pull /data/local/tmp/ce_results ./ce_results 2>/dev/null || true
	@echo "=== Done ===" >&2

clean:
	rm -rf build build_host ce_results
	@echo "  Cleaned"

help:
	@echo "Targets:"
	@echo "  all       - Build all 20 engines for ARM64 (NDK required)"
	@echo "  all_host  - Build for host (PC testing)"
	@echo "  install   - Build + push to device"
	@echo "  run       - Run all engines on device + pull results"
	@echo "  clean     - Remove build artifacts"
	@echo ""
	@echo "Variables:"
	@echo "  ANDROID_NDK_HOME  - Path to NDK (or set NDK_HOME)"
	@echo "  SERIAL            - ADB device serial (optional)"
