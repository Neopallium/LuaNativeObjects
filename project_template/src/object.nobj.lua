--
-- This is an example object from GD example binding
--

object "gdImage" {
	-- Use `ffi_cdef` records to pass extra C type info to FFI.
	ffi_cdef[[
	typedef struct gdImageStruct gdImage;
]],
	-- The first constructor can be called as: gd.gdImage(x,y) or gd.gdImage.new(x,y)
	-- The default name for a constructor is 'new'
  constructor {
    c_call "gdImage *" "gdImageCreate" { "int", "sx", "int", "sy" }
  },
	-- Other constructors can be called by there name: gd.gdImage.newTrueColor(x,y)
  constructor "newTrueColor" {
    c_call "gdImage *" "gdImageCreateTrueColor" { "int", "sx", "int", "sy" }
  },
	-- A named destructor allows freeing of the object before it gets GC'ed.
  destructor "close" {
    c_method_call "void" "gdImageDestroy" {}
  },

  method "color_allocate" {
		-- bindings for simple methods/functions can be generated with `c_method_call` or `c_call`
		-- records, which will generate both Lua API & FFI based bindings for the function.
    c_method_call "int" "gdImageColorAllocate"
      { "int", "r", "int", "g", "int", "b" }
  },

  method "line" {
    c_method_call "void" "gdImageLine"
      { "int", "x1", "int", "y1", "int", "x2", "int", "y2", "int", "colour" }
  },

	-- The next method need extra FFI types & function information.
	ffi_cdef[[
	/* dummy typedef for "FILE" */
	typedef struct FILE FILE;

	FILE *fopen(const char *path, const char *mode);
	int fclose(FILE *fp);

	void gdImagePng(gdImage *im, FILE *out);
]],
	-- This method is more complex and can't be generated with a simple `c_method_call` record.
  method "toPNG" {
		-- Use `var_in`/`var_out` records to define parameters & return values.
    var_in { "const char *", "name" },
		-- Use `c_source` records to provide the C code for this method.
    c_source [[
  FILE *pngout = fopen( ${name}, "wb");
  gdImagePng(${this}, pngout);
  fclose(pngout);
]],
		-- if you want this method to have FFI-based bindings you will need to use a `ffi_source` record
    ffi_source [[
  local pngout = ffi.C.fopen(${name}, "wb")
  C.gdImagePng(${this}, pngout)
  ffi.C.fclose(pngout)
]]
  },
}
