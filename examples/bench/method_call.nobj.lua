object "method_call" {
	c_source[[
typedef struct method_call method_call;

#define DEFAULT_PTR ((method_call *)0xDEADBEEF)

method_call *method_call_create() {
	return DEFAULT_PTR;
}

void method_call_destroy(method_call *call) {
	assert(call == DEFAULT_PTR);
}

int method_call_null(method_call *call) {
	return 0;
}

]],
	-- create object
  constructor {
		c_call "method_call *" "method_call_create" {},
  },
	-- destroy object
  destructor "close" {
		c_method_call "void" "method_call_destroy" {},
  },

  method "simple" {
		c_source[[
	if(${this} != DEFAULT_PTR) {
		luaL_error(L, "INVALID PTR: %p != %p", ${this}, DEFAULT_PTR);
	}
]],
		ffi_source[[
	if(${this} == nil) then
		error(string.format("INVALID PTR: %p == nil", ${this}));
	end
]],
  },

  method "null" {
		c_method_call "int" "method_call_null" {},
  },

}
