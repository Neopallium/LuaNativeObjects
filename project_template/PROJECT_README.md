lua-__mod_name__
=======

Lib__Mod_name__ bindings for Lua.

Installing
----------

### Install lua-__mod_name__:

	curl -O "https://github.com/Neopallium/lua__mod_name__/raw/master/lua-__mod_name__-scm-0.rockspec"
	
	luarocks install lua-__mod_name__-scm-0.rockspec


To re-generating the bindings
-----------------------------

You will need to install LuaNativeObjects and set the CMake variable `USE_PRE_GENERATED_BINDINGS` to FALSE.
By default CMake will use the pre-generated bindings that are include in the project.

Build Dependencies
------------------

Optional dependency for re-generating Lua bindings from `*.nobj.lua` files:

* [LuaNativeObjects](https://github.com/Neopallium/LuaNativeObjects), this is the bindings generator used to convert the `*.nobj.lua` files into a native Lua module.

