c_module "gd" {
use_globals = true,
hide_meta_info = true,
include "gd.h",
subfiles {
  "gdImage.lua"
}
}
