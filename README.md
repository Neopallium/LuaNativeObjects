LuaNativeObjects
================



TODO
----

* Improve 'c_call' record parameter handling:

    c_call "int>1" "func_name"
      { "ObjectType1", "&need_pointer_to_pointer_is_out_var_idx2>2", "ClassObject", "this<1" }

">idx", mark as an output variable with order 'idx' on stack.

"<idx", mark as an input variable with order 'idx' on stack.

"&", this will wrap the variable access with "&(var)".

"*", this will wrap the variable access with "*(var)".

"?", variable is optional use for both input & output values.

"@ref_field_name", use field 'ref_field_name' from struct as a Lua reference, for input field it is set, for output field the reference is pushed.


* Improve class type mapping & push/pop function over-rides:

    object "LuaClassName" "C_struct_name" {
    	-- create a wrapper struct.
    	struct_def [[
    	C_struct_name parent;
    	lua_State     *L;
    	int           ref;
    ]],
      custom_push_func = "name_of_push_function",
    	custom_check_func = "name_of_check_function",
    
    }

* Add better support for enumerations.  Right now you can use a 'package' with constants 'const' records:

    package "ENUM" {
    	const "NONE"      { 0 },
    	const "VAL_1"     { 1 },
    	const "VAL_2"     { 2 },
    	const "VAL_3"     { 3 },
    	const "VAL_4"     { 4 },
    }

# Add better support for bit flag parameters.
   
