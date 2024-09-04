#CFLAGS=-O3 -march=native
CFLAGS=-g -O2 -march=native

all: gd.so bench.so gd.png bench.png

gd.nobj.c: gd*.nobj.lua
	lua ../native_objects.lua -outpath ./ -gen lua gd.nobj.lua

gd.so: gd.nobj.c
	gcc $(CFLAGS) -fPIC -shared -lgd -o $@ gd.nobj.c

bench.nobj.c: bench.nobj.lua bench/*.nobj.lua
	lua ../native_objects.lua -outpath ./ -gen lua bench.nobj.lua

bench.so: bench.nobj.c
	gcc $(CFLAGS) -fPIC -shared -o $@ bench.nobj.c

%.png: %.nobj.dot
	dot -Tpng $< >$@

%.nobj.dot: %.nobj.lua
	lua ../native_objects.lua -outpath ./ -gen dotfile $<

gd.nobj.dot: gd*.nobj.lua
bench.nobj.dot: bench/*.nobj.lua

clean:
	rm -f *.nobj.c *.so *.png *.dot

.PHONY: all clean

