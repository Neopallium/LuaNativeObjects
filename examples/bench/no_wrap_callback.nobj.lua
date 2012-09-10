--
-- C code for NoWrapTestObj object
--
c_source "typedefs" [[
typedef struct NoWrapTestObj NoWrapTestObj;
typedef int (*NoWrapTestObjFunc)(NoWrapTestObj *obj, int idx, void *data);

struct NoWrapTestObj {
	uint32_t some_state;
	NoWrapTestObjFunc func;
	void *func_data;
};

NoWrapTestObj *nowrap_testobj_new() {
	NoWrapTestObj *obj = calloc(1, sizeof(NoWrapTestObj));
	obj->some_state = 0xDEADBEEF;
	return obj;
}

void nowrap_testobj_destroy(NoWrapTestObj *obj) {
	assert(obj->some_state == 0xDEADBEEF);
	free(obj);
}

int nowrap_testobj_register(NoWrapTestObj *obj, NoWrapTestObjFunc func, void *func_data) {
	obj->func = func;
	obj->func_data = func_data;
	return 0;
}

int nowrap_testobj_run(NoWrapTestObj *obj, int run) {
	int rc = 0;
	int i;
	for(i = 0; i < run; i++) {
		rc = obj->func(obj, i, obj->func_data);
		if(rc < 0) break;
	}
	return rc;
}

]]

-- define a C callback function type:
callback_type "NoWrapTestObjFunc" "int" { "NoWrapTestObj *", "this", "int", "idx", "void *", "%data" }
-- callback_type "<callback typedef name>" "<callback return type>" {
--   -- call back function parameters.
--   "<param type>", "%<param name>", -- the '%' marks which parameter holds the wrapped object.
--   "<param type>", "<param name>",
-- }

object "NoWrapTestObj" {
	-- create object
	constructor {
		c_call "NoWrapTestObj *" "nowrap_testobj_new" {},
	},
	-- destroy object
	destructor "close" {
		c_method_call "void" "nowrap_testobj_destroy" {},
	},

	method "register" {
		-- Create an object wrapper for the "NoWrapTestObj" which will hold a reference to the
		-- lua_State & Lua callback function.
		callback { "NoWrapTestObjFunc", "func", "func_data", owner = "this",
			-- C code to run if Lua callback function throws an error.
			c_source[[${ret} = -1;]],
			ffi_source[[${ret} = -1;]],
		},
		-- callback { "<callback typedef name>", "<callback parameter name>", "<parameter to wrap>",
		--   -- c_source/ffi_source/c_call/etc... for error handling.
		-- },
		c_method_call "int" "nowrap_testobj_register" { "NoWrapTestObjFunc", "func", "void *", "func_data" },
	},

	method "run" {
		c_method_call "int" "nowrap_testobj_run" { "int", "num" },
	},

}
