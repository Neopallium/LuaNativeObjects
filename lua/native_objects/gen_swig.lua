-- Copyright (c) 2010 by Robert G. Jakabosky <bobby@neoawareness.com>
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.

--
-- output Swig Lua bindings
--

-- use simple variable naming.
set_variable_format('%s')

--
-- templates
--
local package_new_method = [[
  ${object_name}() { return (void *)1; /* use a fake pointer. */ }
]]

--
-- handle extend records.
--
process_records{
extends = function(self, rec, parent)
	local base = rec.base
	if not base then return end
	-- copy methods from base object
	for name,func in pairs(base.functions) do
		if func._is_method and parent.functions[name] == nil then
			func = func:copy_record()
			func.cast_this_ptr = "(" .. base.c_type .. " *)"
			parent:add_record(func)
		end
	end
end,
}

--
-- to/check/push/delete SWIG Object methods
--
print"============ create to/check/push/delete SWIG Object methods ================="
process_records{
object = function(self, rec, parent)
	rec.lang_type = 'userdata'
	local type_name = 'SWIGTYPE_p_' .. rec.name
	rec._obj_type_name = type_name

	-- create _check/_delete/_push functions
	rec._check = nil
	rec._delete = nil
	rec._to = rec._check
	rec._push = function(self, var, own)
		if own == nil then own = '0' end
		return '  SWIG_NewPointerObj(L, ${' .. var.name .. '}, ' ..
			type_name .. ', ' .. own .. ');\n'
	end
end,
callback_func = function(self, rec, parent)
	rec.lang_type = 'function'

	-- create _check/_delete/_push functions
	rec._check = function(self, var)
		return 'swiglua_ref_get(&(${' .. var.name .. '}));\n' ..
			'  luaL_checktype(${' .. var.name .. '}.L, -1, LUA_TFUNCTION);\n' ..
			'  lua_pop(${' .. var.name .. '}.L, 1);\n'
	end
	rec._delete = function(self, var)
		return 'swiglua_ref_clear(&(${' .. var.name .. '}));\n'
	end
	rec._to = rec._check
	rec._push = function(self, var)
		return 'swiglua_ref_get(&(' .. var .. '));\n'
	end
end,
}

print"============ SWIG Lua bindings ================="
local parsed = process_records{
_modules_out = {},
_includes = {},

-- record handlers
c_module = function(self, rec, parent)
	self._cur_module = rec
	self._modules_out[rec.name] = rec
	rec:write_part("header", {
		'%module ', rec.name, '\n',
[[
%include stdint.i
%include lua_fnptr.i
%nodefaultctor;
%nodefaultdtor;
]]
	})
	rec:write_part("includes", {
		'%{\n'
	})
	rec:write_part("extra_code", {
		'%{\n'
	})
end,
c_module_end = function(self, rec, parent)
	rec:write_part("includes", {
		'%}\n'
	})
	rec:write_part("extra_code", {
		'%}\n'
	})
	self._cur_module = nil
end,
object = function(self, rec, parent)
	rec:add_var('object_name', rec.name)
	-- make typedef for this object
	rec:write_part("typedefs", {
	'typedef struct {\n',
	})
	-- start extend block
	rec:write_part("methods", {
	'%extend ${object_name} {\n',
	})
	-- create fake type for packages.
	if rec.is_package then
		rec:write_part("src", {
			'typedef int ', rec.name, ';\n',
		})
		rec:write_part('methods', package_new_method)
	end
end,
object_end = function(self, rec, parent)
	rec:write_part("typedefs", {
	'} ${object_name};\n\n',
	})
	rec:write_part("methods", {
	'}\n\n'
	})
	local parts = {"typedefs", "methods"}
	-- apply variables to templates.
	rec:vars_parts(parts)
	-- copy parts to parent
	parent:copy_parts(rec, parts)
	-- append extra source code.
	parent:write_part("extra_code", rec:dump_parts{ "src" })
end,
callback_state = function(self, rec, parent)
	rec:add_var('wrap_type', rec.wrap_type)
	rec:add_var('base_type', rec.base_type)
	-- start callback object.
	rec:write_part("wrapper_obj",
	{'/* callback object: ', rec.name, ' */\n',
		'typedef struct {\n',
		'  ', rec.base_type, ' base;\n',
	})
end,
callback_state_end = function(self, rec, parent)
	rec:write_part("wrapper_obj",
	{ rec:dump_parts{"wrapper_callbacks"},
	'} ', rec.wrap_type,';\n',
	})
	-- append extra source code.
	rec:write_part("extra_code", rec:dump_parts{ "wrapper_obj" })
	-- apply variables to parts
	local parts = {"extra_code", "methods"}
	rec:vars_parts(parts)
	-- copy parts to parent
	parent:write_part("src", rec:dump_parts(parts))
end,
extends = function(self, rec, parent)
	local base = rec.base
	if not base then return end
	parent:write_part("typedefs", {
	'  %immutable;\n',
	'  ', rec.base.c_type, ' ', rec.field, ';\n',
	'  %mutable;\n',
	})
end,
include = function(self, rec, parent)
	if self._includes[rec.file] then return end
	self._includes[rec.file] = true
	-- append include file
	self._cur_module:write_part("includes", { '#include "', rec.file, '"\n' })
end,
callback_func = function(self, rec, parent)
	rec.wrapped_type = parent.c_type
	rec.wrapped_type_rec = parent.c_type_rec
	rec.cb_ins = 0
	rec.cb_outs = 0
	-- add callback decl.
	rec:write_part('func_decl', {rec.c_func_decl, ';\n'})
	-- start callback function.
	rec:write_part("cb_head",
	{'/* callback: ', rec.name, ' */\n',
		rec.c_func_decl, ' {\n',
	})
	-- add lua reference to wrapper object.
	parent:write_part('wrapper_callbacks',
	  {'  SWIGLUA_REF ', rec.ref_field, ';\n'})
end,
callback_func_end = function(self, rec, parent)
	local wrapped = rec.wrapped_var
	local wrap_type = parent.wrap_type .. ' *'
	rec:write_part("cb_head",
	{ '  ', wrap_type,' wrap = (',wrap_type,')${', wrapped.name,'};\n',
		'  lua_State *L = wrap->', rec.ref_field,'.L;\n',
	})
	rec:write_part("vars", {'\n  ', rec:_push('wrap->' .. rec.ref_field),})
	-- call lua callback function.
	rec:write_part("src", {'  lua_call(L, ', rec.cb_ins, ', ', rec.cb_outs , ');\n'})
	-- get return value from lua function.
	local ret_out = rec.ret_out
	if ret_out then
		rec:write_part("post", {'  return ${', ret_out.name , '};\n'})
	end
	-- map in/out variables in c source.
	local parts = {"cb_head", "vars", "params", "src", "post"}
	rec:vars_parts(parts)
	rec:vars_parts('func_decl')

	rec:write_part("post", {'}\n\n'})
	parent:write_part('methods', rec:dump_parts(parts))
	parent:write_part('funcdefs', rec:dump_parts('func_decl'))
end,
c_function = function(self, rec, parent)
	rec:add_var('object_name', parent.name)
	-- default no return value.
	rec:add_var('ret', '')
	rec:add_var('ret_type', 'void ')
	rec._ret_name = 'ret'
	-- is this a wrapper function
	if rec.wrapper_obj then
		local wrap_type = rec.wrapper_obj.wrap_type
		rec:write_part("pre",
			{ '    ', wrap_type,' *wrap;\n',
			})
	end
	-- for non-method ignore the 'self' parameter.
	if not rec._is_method then
		rec:write_part("pre",
			{ '    (void)self;\n',
			})
	end
end,
c_function_end = function(self, rec, parent)
	-- is this a wrapper function
	if rec.wrapper_obj then
		local wrap_obj = rec.wrapper_obj
		local wrap_type = wrap_obj.wrap_type
		local callbacks = wrap_obj.callbacks
		if rec.is_destructor then
			rec:write_part("pre",
				{'    wrap = (',wrap_type,' *)${this};\n'})
			for name,cb in pairs(callbacks) do
				rec:write_part("src",
					{'    swiglua_ref_clear(&(wrap->', name,'));\n'})
			end
			rec:write_part("post",
				{'    n_type_free(', wrap_type, ', wrap);\n'})
		elseif rec.is_constructor then
			rec:write_part("pre",
				{
				'    n_new(', wrap_type, ', wrap);\n',
				'    ${this} = &(wrap->base);\n',
				})
		end
	end
	-- prefix non-methods with 'static'
	local prefix =''
	-- check if this method is the object's constructor/destructor
	if rec.is_destructor then
		rec.name = '~' .. parent.name
		rec:add_var('ret_type', '')
	elseif rec.is_constructor then
		rec.name = parent.name
		rec:add_var('ret_type', '')
	end
	rec:write_part("def", {
		'  ', prefix, '${ret_type}', rec.name, '('
	})
	rec:write_part("post", {
		'    return ${', rec._ret_name, '};\n  }\n\n'
	})
	rec:write_part("params", ") {\n")
	-- map in/out variables in c source.
	rec:vars_parts{"def", "params", "pre", "src", "post"}

	parent:write_part("methods", {
		rec:dump_parts{"def", "params", "pre", "src", "post"}
	})
end,
c_source = function(self, rec, parent)
	parent:write_part("src", "  ")
	parent:write_part("src", rec.src)
	parent:write_part("src", "\n")
end,
var_in = function(self, rec, parent)
	if rec.is_this then
		if parent.cast_this_ptr then
			parent:add_var('this', parent.cast_this_ptr .. 'self')
		else
			parent:add_var('this', 'self')
		end
		return
	end
	parent:add_rec_var(rec)
	local c_type = rec.c_type
	local name = rec.name
	local lua = rec.c_type_rec
	-- is a lua reference.
	if lua.is_ref then
		c_type = 'SWIGLUA_REF'
		name = name .. '_ref'
		parent:add_var(name, rec.name)
		parent:add_var(rec.name, rec.cb_func.c_func_name)
		parent:write_part("src",
			{'    wrap->', lua.ref_field, ' = ${', name, '};\n' })
	end
	if parent._next_var then
		parent:write_part("params", ", ")
	else
		parent._next_var = true
	end
	parent:write_part("params", {
		c_type, ' ${', name, '}' })
end,
var_out = function(self, rec, parent)
	assert(parent._ret_rec == nil, "Only supports one 'var_out'")
	parent._ret_name = rec.name
	parent:add_var('ret_type', rec.c_type .. ' ')
	parent:add_rec_var(rec)
	parent:write_part("pre", {
		'    ', rec.c_type, ' ${', rec.name, '};\n'
	})
end,
cb_in = function(self, rec, parent)
	parent:add_rec_var(rec)
	local lua = rec.c_type_rec
	if not rec.is_wrapped_obj then
		parent:write_part("params", { lua:_push(rec) })
		parent.cb_ins = parent.cb_ins + 1
	else
		-- this is the wrapped object parameter.
		parent.wrapped_var = rec
	end
end,
cb_out = function(self, rec, parent)
	parent:add_rec_var(rec)
	parent.cb_outs = parent.cb_outs + 1
	local lua = rec.c_type_rec
	parent:write_part("vars",
		{'  ', rec.c_type, ' ${', rec.name, '};\n'})
	parent:write_part("post",
		{'  ', lua:_to(rec) })
end,
}

local src_file=open_outfile(nil, '.i')
local function src_write(...)
	src_file:write(...)
end

for name,mod in pairs(parsed._modules_out) do
	src_write(
		mod:dump_parts({
			"header",
			"includes",
			"extra_code",
			"typedefs",
			"methods",
			}, "\n\n")
	)
end

print("Finished generating Lua bindings")

