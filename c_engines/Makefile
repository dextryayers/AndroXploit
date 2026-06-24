# extract_droid — single binary universal Android extraction engine
# Cross-compile for ARM64 using Android NDK
# Usage:
#   make              # Build with NDK
#   make install      # Build + push to device
#   make clean        # Remove binary

NDK_HOME ?= $(ANDROID_NDK_HOME)
TOOLCHAIN := $(NDK_HOME)/toolchains/llvm/prebuilt/linux-x86_64
CC := $(TOOLCHAIN)/bin/aarch64-linux-android21-clang
STRIP := $(TOOLCHAIN)/bin/aarch64-linux-android-strip
CFLAGS := -Os -fPIE -static -Wall
SERIAL ?=

$(shell mkdir -p build)

build/extract_droid: extract_droid.c
ifdef NDK_HOME
	$(CC) $(CFLAGS) -o $@ $< -lz
	$(STRIP) $@
	@echo "  Built: $@ ($$(du -h $@ | cut -f1))"
else
	@echo "ANDROID_NDK_HOME not set. Try: make build_host"
endif

build_host: extract_droid.c
	gcc -Os -Wall -DTARGET_HOST -o build/extract_droid $< -lz
	@echo "  Host build: build/extract_droid"

install: build/extract_droid
	adb $(if $(SERIAL),-s $(SERIAL)) push build/extract_droid /data/local/tmp/
	adb $(if $(SERIAL),-s $(SERIAL)) shell chmod 755 /data/local/tmp/extract_droid
	@echo "  Pushed to device"

run: install
	adb $(if $(SERIAL),-s $(SERIAL)) shell "/data/local/tmp/extract_droid /data/local/tmp/extract_results --all"
	adb $(if $(SERIAL),-s $(SERIAL)) pull /data/local/tmp/extract_results ./results/

pull:
	adb $(if $(SERIAL),-s $(SERIAL)) pull /data/local/tmp/extract_droid_result.json ./results/ 2>/dev/null || true

clean:
	rm -rf build
	@echo "  Cleaned"

.PHONY: all install run pull clean build_host
