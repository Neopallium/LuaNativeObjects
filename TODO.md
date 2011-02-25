TODO
====

* Documentation or examples!

* Improve `c_call` record parameter handling:

`@ref_name`, use field `ref_name` in the C object `this->ref_name` as a Lua reference, for input field it is set, for output field the reference is pushed.


* Improve class type mapping & push/pop function over-rides:

<pre>
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
</pre>

* Add better support for enumerations.  Right now you can use a `package` with constants `const` records:

<pre>
    package "ENUM" {
    	const "NONE"      { 0 },
    	const "VAL_1"     { 1 },
    	const "VAL_2"     { 2 },
    	const "VAL_3"     { 3 },
    	const "VAL_4"     { 4 },
    }
</pre>

# Add better support for bit flag parameters.
   
