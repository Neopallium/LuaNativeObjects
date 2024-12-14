package = "LuaNativeObjects"
version = "scm-0"
source = {
	url = "git://github.com/Neopallium/LuaNativeObjects.git",
}
description = {
	summary = "A Lua bindings generator.",
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
