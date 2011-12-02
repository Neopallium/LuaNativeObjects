#CFLAGS=-O3 -march=native
CFLAGS=-g -O2 -march=native

all: gd.so bench.so

gd.nobj.c: gd*.nobj.lua
	lua ../native_objects.lua -outpath ./ -gen lua gd.nobj.lua

gd.so: gd.nobj.c
	gcc $(CFLAGS) -fPIC -shared -lgd -o $@ gd.nobj.c

bench.nobj.c: bench.nobj.lua bench/*.nobj.lua
	lua ../native_objects.lua -outpath ./ -gen lua bench.nobj.lua

bench.so: bench.nobj.c
	gcc $(CFLAGS) -fPIC -shared -o $@ bench.nobj.c

clean:
	rm -f *.nobj.c *.so test.png

.PHONY: all clean

