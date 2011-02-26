#!/usr/bin/env lua

package	= 'lua-__mod_name__'
version	= 'scm-0'
source	= {
	url	= '__project_git_url__'
}
description	= {
	summary	= "LuaNativeObjects project template.",
	detailed	= '',
	homepage	= '__project_homepage__',
	license	= 'MIT',
	maintainer = "__authors_name__",
}
dependencies = {
	'lua >= 5.1',
}
external_dependencies = {
	__MOD_NAME__ = {
		header = "__mod_name__.h",
		library = "__mod_name__",
	}
}
build	= {
	type = "builtin",
	modules = {
		__mod_name__ = {
			sources = { "src/pre_generated-__mod_name__.nobj.c" },
			libraries = { "__mod_name__" },
		}
	}
}
