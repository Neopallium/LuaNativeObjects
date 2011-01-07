object "gdImage" {
  include "gd.h",
  method_new {
    c_call "gdImage *" "gdImageCreate" { "int", "sx", "int", "sy" }
  },
  method_delete {
    c_call "void" "gdImageDestroy" {}
  },
  method "color_allocate" {
    c_call "int" "gdImageColorAllocate"
      { "int", "r", "int", "g", "int", "b" }
  },
  method "line" {
    c_call "void" "gdImageLine"
      { "int", "x1", "int", "y1", "int", "x2", "int", "y2", "int", "colour" }
  },
  method "toPNG" {
    var_in { "const char *", "name" },
    c_source [[
  FILE *pngout = fopen( ${name}, "wb");
  gdImagePng(${this}, pngout);
  fclose(pngout);
]]
  },
}
