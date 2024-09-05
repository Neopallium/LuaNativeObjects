CFLAGS=-g -O2 -march=native

all: gd.so bench.so gd.png bench.png

test: gd.so
	lua test_gd.lua

gd.so: LDLIBS=-lgd
gd.nobj.c gd.nobj.dot: gd*.nobj.lua
bench.nobj.c bench.nobj.dot: bench/*.nobj.lua

%.nobj.c %.nobj.ffi.lua: %.nobj.lua
	native_objects.lua -outpath ./ -gen lua $<

%.so: %.nobj.c
	$(CC) $(CFLAGS) $(LDFLAGS) -fPIC -shared $(LDLIBS) -o $@ $<

%.nobj.dot: %.nobj.lua
	native_objects.lua -outpath ./ -gen dotfile $<

%.png: %.nobj.dot
	dot -Tpng $< >$@

clean:
	rm -f *.nobj.c *.nobj.ffi.lua *.so *.png *.dot

.PHONY: all test clean
