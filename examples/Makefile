
all: gd.so

gd.nobj.c: *.nobj.lua
	lua ../native_objects.lua -outpath ./ -gen lua gd.nobj.lua

gd.so: gd.nobj.c
	gcc -fPIC -shared -lgd -o $@ gd.nobj.c

clean:
	rm -f gd.nobj.c gd.so test.png

.PHONY: all clean

