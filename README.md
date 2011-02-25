LuaNativeObjects
================



Marking variable
----------------

	c_call "int>1" "func_name"
	  { "ObjectType1", "&need_pointer_to_pointer_is_out_var_idx2>2", "ClassObject", "this<1" }

`<idx`, mark as an input variable with order `idx` on stack.

`>idx`, mark as an output variable with order `idx` on stack.

`!`, mark will cause owner-ship of an object to transfer between C & Lua.
For output variables Lua will take owner-ship the object instance and free it when the object's `__gc` is called.
For input variables Lua will give-up owner-ship of the object and only keep a reference to the object.

`#var`, reference the length of the named variable `var`.

`&`, this will wrap the variable access with `&(var)`.

`*`, this will wrap the variable access with `*(var)`.

`?`, variable is optional use for both input & output values.

