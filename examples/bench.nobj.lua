
-- make generated variable nicer.
set_variable_format "%s%d"

-- define the 'bench' module
c_module "bench" {
use_globals = false,
hide_meta_info = false,

luajit_ffi = true,
--luajit_ffi = false,

luajit_ffi_load_cmodule = true,

-- here we include the bindings file for each object into this module.
subfiles {
  "bench/method_call.nobj.lua",
  "bench/callback.nobj.lua"
}
}
