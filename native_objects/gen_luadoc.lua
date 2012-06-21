-- Copyright (c) 2012 by Robert G. Jakabosky <bobby@neoawareness.com>
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

local tconcat = table.concat

-- re-map meta-methods.
local lua_meta_methods = {
__str__ = '__tostring',
__eq__ = '__eq',
delete = '__gc',
-- Lua metamethods
__add = '__add',
__sub = '__sub',
__mul = '__mul',
__div = '__div',
__mod = '__mod',
__pow = '__pow',
__unm = '__unm',
__len = '__len',
__concat = '__concat',
__eq = '__eq',
__lt = '__lt',
__le = '__le',
__gc = '__gc',
__tostring = '__tostring',
__index = '__index',
__newindex = '__newindex',
}

local function ctype_to_name(ctype)
	if ctype.lang_type == 'userdata' then
	elseif ctype.lang_type == 'function' then
		return "Lua function"
	else
		return ctype.lang_type or ctype.name
	end
	return ctype.name
end

function get_type_link(rec)
	if rec._rec_type == 'object' then
		return '<a href="' .. rec.name .. '.html">' .. rec.name ..'</a>'
	else
		return '<code>' .. ctype_to_name(rec) .. '</code>'
	end
end

print"============ Lua Documentation ================="

local parsed = process_records{
_modules_out = {},

-- record handlers
c_module = function(self, rec, parent)
	local module_c_name = rec.name:gsub('(%.)','_')
	rec:add_var('module_c_name', module_c_name)
	rec:add_var('module_name', rec.name)
	rec:add_var('object_name', rec.name)
	rec.objects = {}
	self._cur_module = rec
	self._modules_out[rec.name] = rec

	rec:write_part("doc_header", {
		'--- Module ${object_name}.\n',
		'--\n',
	})
end,
c_module_end = function(self, rec, parent)
	self._cur_module = nil

	rec:write_part("doc_footer", {
		'module("${object_name}")\n\n',
		})
	local parts = { "doc_header", "doc_src", "doc_footer", "doc_funcs" }
	rec:vars_parts(parts)
	rec:write_part("doc_out", rec:dump_parts(parts))
end,
error_code = function(self, rec, parent)
	rec:add_var('object_name', rec.name)
end,
error_code_end = function(self, rec, parent)
end,
object = function(self, rec, parent)
	self._cur_module.objects[rec.name] = rec
	rec:add_var('object_name', rec.name)
	parent:write_part("doc_footer", {
		'-- <br />Class ', get_type_link(rec),'\n',
	})
	rec:write_part("doc_header", {
		'--- Class "${object_name}".\n',
		'--\n',
	})
	rec:write_part("doc_subclasses", {
		'-- <br />\n',
	})
end,
object_end = function(self, rec, parent)
	rec:write_part("doc_footer", {
		'module("${object_name}")\n\n',
		})
	-- copy generated luadocs to parent
	local parts = { "doc_header", "doc_src", "doc_footer", "doc_funcs" }
	rec:vars_parts(parts)
	rec:write_part("doc_out", rec:dump_parts(parts))
	-- copy methods to sub-classes
	local subs = rec.subs
	if subs then
		local methods = rec:dump_parts("doc_for_subs")
		for i=1,#subs do
			local sub = subs[i]
			sub.base_methods = (sub.base_methods or '') .. methods
		end
	end
end,
doc = function(self, rec, parent)
	parent:write_part("doc_src", {
		'-- ',rec.text:gsub("\n","\n-- "),'\n',
	})
end,
callback_state = function(self, rec, parent)
end,
callback_state_end = function(self, rec, parent)
end,
include = function(self, rec, parent)
end,
define = function(self, rec, parent)
end,
extends = function(self, rec, parent)
	assert(not parent.is_package, "A Package can't extend anything: package=" .. parent.name)
	local base = rec.base
	if base == nil then return end
	parent:write_part("doc_footer", {
		'-- Extends ', get_type_link(base),'<br />\n',
	})
	base:write_part("doc_subclasses", {
		'-- Subclass ', get_type_link(parent),'<br />\n',
	})
	-- add methods/fields/constants from base object
	for name,val in pairs(base.name_map) do
		-- make sure sub-class has not override name.
		if parent.name_map[name] == nil or parent.name_map[name] == val then
			parent.name_map[name] = val
			if val._is_method and not val.is_constructor then
				parent.functions[name] = val
			elseif val._rec_type == 'field' then
				parent.fields[name] = val
			elseif val._rec_type == 'const' then
				parent.constants[name] = val
			end
		end
	end
end,
extends_end = function(self, rec, parent)
end,
callback_func = function(self, rec, parent)
	rec.wrapped_type = parent.c_type
	rec.wrapped_type_rec = parent.c_type_rec
	-- start callback function.
	rec:write_part("doc_src", {
		'--- callback: ', rec.name, '\n',
		'--\n',
		'-- @name ', rec.name, '\n',
	})
	rec:write_part("doc_func", {
		'function ', rec.name, '('
	})
end,
callback_func_end = function(self, rec, parent)
	-- end luddoc for function
	rec:write_part("doc_func", {
		')\nend\n'
	})
	-- map in/out variables in c source.
	local parts = {"doc_header", "doc_src", "doc_footer", "doc_func"}
	rec:vars_parts(parts)

	parent:write_part('doc_funcs', { rec:dump_parts(parts), "\n\n" })
end,
dyn_caster = function(self, rec, parent)
end,
dyn_caster_end = function(self, rec, parent)
end,
c_function = function(self, rec, parent)
	if rec._is_hidden then return end
	rec:add_var('object_name', parent.name)

	local name = rec.name
	if rec._is_meta_method and not rec.is_destructor then
		name = lua_meta_methods[name]
	end
	rec:add_var('func_name', name)

	local desc = ''
	local prefix = ''
	if rec._is_method then
		if rec.is_constructor then
			desc = "Create a new ${object_name} object."
			prefix = "${object_name}."
		elseif rec.is_destructor then
			desc = "Destroy this object (will be called by Garbage Collector)."
			prefix = "${object_name}:"
		elseif rec._is_meta_method then
			desc = "object meta method."
			prefix = "${object_name}_mt:"
		else
			desc = "object method."
			prefix = "${object_name}:"
		end
	else
		desc = "module function."
		prefix = "${object_name}."
	end
	-- generate luadoc stub function
	rec:write_part("doc_src", {
		'--- ', desc, '\n',
		'--\n',
	})
	rec:write_part("doc_func", {
		'-- @name ', prefix, '${func_name}\n',
		'function ', prefix, name, '('
	})
end,
c_function_end = function(self, rec, parent)
	if rec._is_hidden then return end

	local params = {}
	for i=1,#rec do
		local var = rec[i]
		local rtype = var._rec_type
		local name = var.name
		if rtype == 'var_in' then
			if not var.is_this and name ~= 'L' then
				params[#params + 1] = var.name
			end
		end
	end
	params = tconcat(params, ', ')
	-- end luddoc for function
	rec:write_part("doc_func", {
		params, ')\nend'
	})
	local parts = {"doc_header", "doc_src", "doc_footer", "doc_func"}
	rec:vars_parts(parts)
	if rec._is_method and not rec.is_constructor then
		parent:write_part("doc_for_subs", {rec:dump_parts(parts), "\n\n"})
	end
	parent:write_part("doc_funcs", {rec:dump_parts(parts), "\n\n"})
end,
c_source = function(self, rec, parent)
end,
doc_export = function(self, rec, parent)
end,
doc_source = function(self, rec, parent)
end,
var_in = function(self, rec, parent)
	-- no need to add code for 'lua_State *' parameters.
	if rec.c_type == 'lua_State *' and rec.name == 'L' then return end
	if rec.is_this then return end
	local desc = ''
	if rec.desc then
		desc = rec.desc .. '.  '
	end
	if rec.c_type == '<any>' then
		desc = desc .. "Multiple types accepted."
	else
		desc = desc .."Must be of type " .. get_type_link(rec.c_type_rec) .. "."
	end
	parent:write_part("doc_footer",
		{'-- @param ', rec.name, ' ', desc, '\n'})
end,
var_out = function(self, rec, parent)
	if rec.is_length_ref or rec.is_temp then
		return
	end
	-- push Lua value onto the stack.
	local error_code = parent._has_error_code
	local var_type = get_type_link(rec.c_type_rec)
	if error_code == rec then
		if rec._rec_idx == 1 then
			parent:write_part("doc_footer", {
				'-- @return <code>true</code> if no error.\n',
				'-- @return Error string.\n',
				})
		else
			parent:write_part("doc_footer", {
				'-- @return Error string.\n',
				})
		end
	elseif rec.no_nil_on_error ~= true and error_code then
		parent:write_part("doc_footer", {
			'-- @return ', var_type, ' or <code>nil</code> on error.\n',
			})
	elseif rec.is_error_on_null then
		parent:write_part("doc_footer", {
			'-- @return ', var_type, ' or <code>nil</code> on error.\n',
			'-- @return Error string.\n',
			})
	else
		parent:write_part("doc_footer", {
			'-- @return ', var_type, '.\n',
			})
	end
end,
cb_in = function(self, rec, parent)
	parent:write_part("doc_footer",
		{'-- @param ', rec.name, '\n'})
end,
cb_out = function(self, rec, parent)
	parent:write_part("doc_footer",
		{'-- @return ', rec.name, '\n'})
end,
}

local lfs = require"lfs"
local src_file
local function src_write(...)
	src_file:write(...)
end

local function dump_module(mod, path)
	path = path or ''
	lfs.mkdir(get_outpath(path))
	src_file = open_outfile(path .. mod.name .. '.luadoc')
	-- write header
	src_write[[
--
-- Warning: AUTOGENERATED DOCS.
--

]]
	src_write(
		mod:dump_parts({
			"doc_out",
			}),
		(mod.base_methods or '')
	)
end

local function dump_modules(modules, path)
	path = path or ''
	for name,mod in pairs(modules) do
		dump_module(mod, path)
		local objects = mod.objects
		if objects then
			dump_modules(objects, path .. mod.name .. '/')
		end
	end
end

dump_modules(parsed._modules_out)

print("Finished generating luadoc stubs")

