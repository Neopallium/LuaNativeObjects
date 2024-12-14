package = "LuaNativeObjects-luadoc"
version = "0.5-0"
source = {
	url = "git://github.com/Neopallium/LuaNativeObjects.git",
  branch = "v0.5",
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
  "luanativeobjects >= 0.5",
  "luafilesystem",
}
build = {
	type = "builtin",
  modules = {
		['native_objects.gen_luadoc'] = "native_objects/gen_luadoc.lua",
  },
}
