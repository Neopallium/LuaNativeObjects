LuaNativeObjects
================

This is a bindings generator for Lua & LuaJIT2.  It can be used to generator both standard Lua C API & LuaJIT2 FFI based bindings for C libraries.  Both standard & FFI based bindings are packaged in a single shared library (.so or .dll) file.  When the module is loaded in LuaJIT2 (please use git HEAD version of LuaJIT2 for now) it will try to load the FFI-based bindings in-place of the standard Lua API bindings.

This bindings generator is design to create Object based bindings, instead of simple procedural bindings.  So if you have a C structure (your object) and a set of C functions (your object's methods) that work on that structure, then you can turn them into a nice Lua object.

It is still possible to generator procedural bindings for C functions that don't belong to an object (use a `package` record instead of an `object` record).


Lua bindings using this generator
---------------------------------

* [Lua-zmq](http://github.com/Neopallium/lua-zmq)
* [Luagit2](http://github.com/Neopallium/luagit2)

Example bindings
----------------

This example bindings code is take from the 'examples' folder.

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
	}

Marking input & output variables
--------------------------------

The `c_call` & `c_method_call` records have support for annotating the return type and function parameters to control how the generated bindings work.

	c_call "int>1" "func_name"
	  { "ObjectType1", "&need_pointer_to_pointer_is_out_var_idx2>2", "ClassObject", "this<1" }

`<idx`, mark as an input parameter from Lua.  The `idx` value controls the order of input parameters.

`>idx`, mark as an output that will be returned from the function back to Lua.  The `idx` value controls the order of output values as returned to Lua.

`!`, mark will cause owner-ship of an object to transfer between C & Lua.
For output variables Lua will take owner-ship the object instance and free it when the object's `__gc` is called.
For input variables Lua will give-up owner-ship of the object and only keep a reference to the object.

`#var`, reference the length of the named variable `var`.  This is used for 'string' type input parameters.

`?`, mark the input parameter as optional.

`&`, this will wrap the variable access with `&(var)`.

`*`, this will wrap the variable access with `*(var)`.

