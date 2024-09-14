LUA_VERSION=5.4
DESTDIR=
PREFIX=/usr/local
PREFIX_EXEC=$(PREFIX)
BINDIR=$(PREFIX_EXEC)/bin
DATADIR=$(PREFIX)/share
LUA_LMOD=$(DATADIR)/lua/$(LUA_VERSION)

all:
	@echo Nothing to do

install:
	install -m644 -Dt $(DESTDIR)$(LUA_LMOD)/native_objects native_objects/*.lua
	install -m755 -Dt $(DESTDIR)$(BINDIR) native_objects.lua

uninstall:
	rm -rf $(DESTDIR)$(LUA_LMOD)/native_objects
	rm -f $(DESTDIR)$(BINDIR)/native_objects.lua

.PHONY: all install uninstall
