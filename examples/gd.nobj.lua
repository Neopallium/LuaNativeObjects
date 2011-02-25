-- define the 'gd' module
c_module "gd" {
-- when set to true all objects will be registered as a global for easy access.
use_globals = true,

-- enable FFI bindings support.
luajit_ffi = true,

-- load GD shared library.
ffi_load"gd",

-- include library's header file
include "gd.h",

-- here we include the bindings file for each object into this module.
subfiles {
  "gdImage.nobj.lua"
}
}
