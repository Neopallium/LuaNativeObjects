package = "LuaNativeObjects-luadoc"
version = "scm-0"
source = {
	url = "git://github.com/Neopallium/LuaNativeObjects.git",
}
description = {
	summary = "A Lua bindings generator.  Backedn to generate luadocs.",
  detailed = [[
A luadocs generator backend for LuaNativeObjects.
	]],
	homepage = "https://github.com/Neopallium/LuaNativeObjects",
	license = "MIT/X11",
}
dependencies = {
	"lua >= 5.1, < 5.5",
  "luanativeobjects",
  "luafilesystem",
}
build = {
	type = "builtin",
  modules = {
		['native_objects.gen_luadoc'] = "native_objects/gen_luadoc.lua",
  },
}
