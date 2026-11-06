# Makefile for libbr5longpaper.so and libsane-brother5lp.so.1
#
# Build:               make
# Arch package:        cd pkg && makepkg -si
# Manual install:      sudo make install
# Clean:               make clean
# Check:               make check-deps
#
# Two outputs:
#   libbr5longpaper.so         — USB hook, loaded by the backend
#   libsane-brother5lp.so.1    — SANE backend for scan-long and GUI apps
#
# Install also writes /etc/sane.d/dll.d/brother5lp, which registers the
# backend; scanning apps then see "Brother DS-740D [Long Paper]" alongside
# the regular device.  No LD_PRELOAD or patchelf required.

CC      ?= gcc
CFLAGS  ?= -O2

# Needed whatever the caller sets.  These stay out of CFLAGS and LDFLAGS because
# makepkg and other packagers export their own, which would replace them.
REQUIRED_CFLAGS = -Wall -Wextra -fPIC -shared
REQUIRED_LIBS   = -ldl -lpthread

PREFIX     ?= /usr/local
LIBDIR     ?= $(PREFIX)/lib
SANEDIR    ?= $(LIBDIR)/sane
SYSCONFDIR ?= /etc

SRCS_HOOK    = src/longpaper_hook.c
SRCS_BACKEND = src/sane_backend.c

LIB_HOOK    = libbr5longpaper.so
LIB_BACKEND = libsane-brother5lp.so.1

# Try pkg-config first; fall back to common paths
LIBUSB_CFLAGS  := $(shell pkg-config --cflags libusb-1.0 2>/dev/null \
                           || echo -I/usr/include/libusb-1.0)
LIBUSB_LDFLAGS := $(shell pkg-config --libs   libusb-1.0 2>/dev/null \
                           || echo -lusb-1.0)

SANE_CFLAGS := -I/usr/include/sane

ALL_CFLAGS = $(CPPFLAGS) $(CFLAGS) $(REQUIRED_CFLAGS) $(LIBUSB_CFLAGS) $(SANE_CFLAGS)

# The hook never calls libusb directly, it finds it with dlsym(RTLD_NEXT).  Keep
# libusb as a dependency anyway, or --as-needed drops it and the hook's private
# link namespace loads in a different order from the one tested on hardware.
ALL_LIBS   = -Wl,--push-state,--no-as-needed $(LIBUSB_LDFLAGS) -Wl,--pop-state $(REQUIRED_LIBS)

.PHONY: all hook backend install clean check-deps

all: hook backend

hook: $(LIB_HOOK)

backend: $(LIB_BACKEND)

$(LIB_HOOK): $(SRCS_HOOK) | check-deps
	$(CC) $(ALL_CFLAGS) $(LDFLAGS) -Wl,-soname,$(LIB_HOOK) -o $@ $^ $(ALL_LIBS)
	@echo "Built $(LIB_HOOK)"

$(LIB_BACKEND): $(SRCS_BACKEND) | check-deps
	$(CC) $(ALL_CFLAGS) $(LDFLAGS) -Wl,-soname,$(LIB_BACKEND) -o $@ $^ $(ALL_LIBS)
	@echo "Built $(LIB_BACKEND)"

install: all
	install -Dm755 $(LIB_HOOK)    $(DESTDIR)$(LIBDIR)/$(LIB_HOOK)
	install -Dm755 $(LIB_BACKEND) $(DESTDIR)$(SANEDIR)/$(LIB_BACKEND)
	ln -sf $(LIB_BACKEND) $(DESTDIR)$(SANEDIR)/libsane-brother5lp.so
	install -Dm755 scan_long.sh   $(DESTDIR)$(PREFIX)/bin/scan-long
	install -d $(DESTDIR)$(SYSCONFDIR)/sane.d/dll.d
	echo brother5lp > $(DESTDIR)$(SYSCONFDIR)/sane.d/dll.d/brother5lp
	@echo ""
	@echo "Installed.  Open Simple Scan / XSane and select"
	@echo "  'Brother DS-740D [Long Paper]' or 'Brother ADS-1200 [Long Paper]'"
	@echo "Long paper is single-sided only."

clean:
	rm -f $(LIB_HOOK) $(LIB_BACKEND)

check-deps:
	@echo "Checking build dependencies..."
	@command -v $(CC) >/dev/null 2>&1 || \
	    { echo "ERROR: $(CC) not found. Install gcc."; exit 1; }
	@test -f /usr/include/sane/sane.h || \
	    { echo "ERROR: sane/sane.h not found."; \
	      echo "  Arch:   sudo pacman -S sane"; \
	      echo "  Debian: sudo apt install libsane-dev"; \
	      exit 1; }
	@(pkg-config --exists libusb-1.0 2>/dev/null || \
	  test -f /usr/include/libusb-1.0/libusb.h) || \
	    { echo "ERROR: libusb-1.0 headers not found."; \
	      echo "  Arch:   sudo pacman -S libusb"; \
	      echo "  Debian: sudo apt install libusb-1.0-0-dev"; \
	      exit 1; }
	@echo "  OK"

