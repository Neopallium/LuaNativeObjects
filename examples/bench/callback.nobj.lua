--
-- C code for TestObj object
--
c_source "typedefs" [[
typedef struct TestObj TestObj;
typedef int (*TestObjFunc)(TestObj *obj, int idx);

struct TestObj {
	uint32_t some_state;
	TestObjFunc func;
};

void testobj_init(TestObj *obj, TestObjFunc func) {
	obj->some_state = 0xDEADBEEF;
	obj->func = func;
}

void testobj_destroy(TestObj *obj) {
	assert(obj->some_state == 0xDEADBEEF);
}

int testobj_run(TestObj *obj, int run) {
	int rc = 0;
	int i;
	for(i = 0; i < run; i++) {
		rc = obj->func(obj, i);
		if(rc < 0) break;
	}
	return rc;
}

]]

-- define a C callback function type:
callback_type "TestObjFunc" "int" { "TestObj *", "%this", "int", "idx" }
-- callback_type "<callback typedef name>" "<callback return type>" {
--   -- call back function parameters.
--   "<param type>", "%<param name>", -- the '%' marks which parameter holds the wrapped object.
--   "<param type>", "<param name>",
-- }

object "TestObj" {
	-- create object
  constructor {
		-- Create an object wrapper for the "TestObj" which will hold a reference to the
		-- lua_State & Lua callback function.
		callback { "TestObjFunc", "func", "this",
			-- C code to run if Lua callback function throws an error.
			c_source[[${ret} = -1;]],
			ffi_source[[${ret} = -1;]],
		},
		-- callback { "<callback typedef name>", "<callback parameter name>", "<parameter to wrap>",
		--   -- c_source/ffi_source/c_call/etc... for error handling.
		-- },
		c_call "void" "testobj_init" { "TestObj *", "this", "TestObjFunc", "func" },
  },
	-- destroy object
  destructor "close" {
		c_method_call "void" "testobj_destroy" {},
  },

  method "run" {
		c_method_call "int" "testobj_run" { "int", "num" },
  },

}
