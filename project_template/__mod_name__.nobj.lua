
c_module "__mod_name__" {

-- enable FFI bindings support.
luajit_ffi = true,

-- load __MOD_NAME__ shared library.
ffi_load"__mod_name__",

include "__mod_name__.h",

subfiles {
"src/object.nobj.lua",
},
}

