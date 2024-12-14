package = "LuaNativeObjects"
version = "scm-0"
source = {
	url = "git://github.com/Neopallium/LuaNativeObjects.git",
}
description = {
	summary = "A Lua bindings generator.",
  detailed = [[
This is a bindings generator for Lua & LuaJIT2.  It can be used to generator both standard Lua C API & LuaJIT2 FFI based bindings for C libraries.  Both standard & FFI based bindings are packaged in a single shared library (.so or .dll) file.  When the module is loaded in LuaJIT2 (please use git HEAD version of LuaJIT2 for now) it will try to load the FFI-based bindings in-place of the standard Lua API bindings.

This bindings generator is design to create Object based bindings, instead of simple procedural bindings.  So if you have a C structure (your object) and a set of C functions (your object's methods) that work on that structure, then you can turn them into a nice Lua object.
]],
	homepage = "https://github.com/Neopallium/LuaNativeObjects",
	license = "MIT/X11",
}
dependencies = {
	"lua >= 5.1, < 5.5",
}
build = {
	type = "builtin",
  modules = {
		['native_objects.gen_dump'] = "native_objects/gen_dump.lua",
		['native_objects.gen_lua_ffi'] = "native_objects/gen_lua_ffi.lua",
		['native_objects.gen_lua'] = "native_objects/gen_lua.lua",
		['native_objects.gen_simple'] = "native_objects/gen_simple.lua",
		['native_objects.gen_swig'] = "native_objects/gen_swig.lua",
		['native_objects.interfaces'] = "native_objects/interfaces.lua",
		['native_objects.lang_lua'] = "native_objects/lang_lua.lua",
		['native_objects.lang_swig'] = "native_objects/lang_swig.lua",
		['native_objects.record'] = "native_objects/record.lua",
		['native_objects.stages'] = "native_objects/stages.lua",
		['native_objects'] = "native_objects.lua",
  },
  install = {
    bin = { "bin/native_objects" }
  }
}
