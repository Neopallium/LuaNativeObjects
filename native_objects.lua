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

-- add path of native_objects.lua to package.path
local native_objects_path=(arg[0]):gsub("native_objects.lua", "?.lua;")
package.path = package.path .. native_objects_path

require("record")

local tinsert=table.insert
local tappend=function(dst,src) for _,v in pairs(src) do dst[#dst+1] = v end end
local tconcat=table.concat

--
-- Switch language we are generating bindings for.
--
local gen_lang="lua"

-- gen_module module
local gen_module="dump"

-- global mapping of c_types to records.
local c_types={}
local function reset()
	clear_all_records()
	c_types={}
end

--
-- C-Type functions
--
local function strip_c_type(c_type)
	-- strip const from c_type
	c_type = c_type:gsub("^%s*const%s*","")
	-- strip spaces from c_type
	c_type = c_type:gsub("%s*","")
	return c_type
end

function new_c_type(c_type, rec)
	c_types[strip_c_type(c_type)] = rec
end

local function real_c_type_resolver(self)
	local c_type = self.c_type
	local _type = c_types[c_type]
	-- if type unknown see if it is a pointer.
	if _type == nil and c_type ~= "void*" and c_type:find("*",1,true) ~= nil then
		-- map it to a generic pointer.
		print("WARNING maping un-resolved pointer type '" .. c_type .."' to 'void *'")
		return resolve_c_type("void*")
	end
	if _type == nil then
		print("Unkown type: " .. c_type)
	end
	rawset(self, "_type", _type)
	return _type
end
local resolve_meta = {
__index = function(self, key)
	local _type = rawget(self, "_type") -- check for cached type.
	if _type == nil then
		-- try to resolve c_type dynamically
		_type = real_c_type_resolver(self)
	end
	if _type then
		return _type[key]
	else
		print("type not resolved yet: " .. self.c_type)
	end
	return nil
end,
__newindex = function(self, key, value)
	local _type = rawget(self, "_type") -- check for cached type.
	if _type == nil then
		-- try to resolve c_type dynamically
		_type = real_c_type_resolver(self)
	end
	if _type then
		_type[key] = value
	else
		print("type not resolved yet: " .. self.c_type)
	end
end,
__len = function(self)
	local _type = rawget(self, "_type") -- check for cached type.
	if _type == nil then
		-- try to resolve c_type dynamically
		_type = real_c_type_resolver(self)
	end
	if _type then
		return #_type
	else
		error("type not resolved yet: " .. self.c_type)
	end
end,
__eq = function(op1, op2)
	return op1.c_type == op2.c_type
end,
}
local cache_resolvers={}
function resolve_c_type(c_type)
	local c_type = strip_c_type(c_type)
	local resolver = cache_resolvers[c_type]
	if resolver == nil then
		resolver = {c_type = c_type}
		setmetatable(resolver, resolve_meta)
		cache_resolvers[c_type] = resolver
	end
	return resolver
end

local function resolve_rec(rec)
	if rec.c_type ~= nil and rec.c_type_rec == nil then
		rec.c_type_rec = resolve_c_type(rec.c_type)
	end
end

--
-- Record functions -- Used to create new records.
--
local function ctype(name, rec, rec_type)
	rec = make_record(rec, rec_type)
	-- record's c_type
	rec.name = name
	rec.c_type = name
	rec._is_c_type = true
	-- map the c_type to this record
	new_c_type(name, rec)
	return rec
end

function basetype(name)
	return function (lang_type)
	return function (default)
	-- make it an basetype record.
	rec = ctype(name,{},"basetype")
	-- lang type
	rec.lang_type = lang_type
	-- default value
	rec.default = default
	return rec
end
end
end

function error_code(name)
	return function (c_type)
	return function (rec)
	-- make error_code record
	ctype(name,rec,"error_code")
	rec.c_type = c_type
	-- mark this type as an error code.
	rec._is_error_code = true
end
end
end

function object(name)
	return function (rec)
	-- make it an object record.
	userdata_type = rec.userdata_type or 'generic'
	rec.userdata_type = userdata_type
	rec.has_obj_flags = true
	if userdata_type == 'generic' or userdata_type == 'embed' or userdata_type == 'simple ptr' then
		ctype(name .. " *", rec,"object")
		rec.name = name
		-- map the c_type to this record
		new_c_type(name, rec)
		if userdata_type == 'embed' or userdata_type == 'simple ptr' then
			rec.no_weak_ref = true
			rec.has_obj_flags = false
		end
	else
		rec.no_weak_ref = true
		if userdata_type == 'simple' or userdata_type == 'simple ptr' then
			rec.has_obj_flags = false
		end
		ctype(name, rec, "object")
	end
	-- check object type flags.
	if rec.no_weak_ref == nil then
		rec.no_weak_ref = false
	end
	-- check if this type generates errors on NULLs
	if rec.error_on_null then
		-- create 'is_error_check' code
		rec.is_error_check = function(rec)
			return "(NULL == ${" .. rec.name .. "})"
		end
		rec.ffi_is_error_check = function(rec)
			return "(nil == ${" .. rec.name .. "})"
		end
	end
	return rec
end
end

function submodule(name)
	return function (rec)
	rec = object(name)(rec)
	rec.register_as_submodule = true
	return rec
end
end

function package(name)
	if type(name) == 'table' then
		local rec = name
		rec = object('_MOD_GLOBAL_')(rec)
		rec.is_package = true
		rec.is_mod_global = true
		return rec
	end
	return function (rec)
	rec = object(name)(rec)
	rec.is_package = true
	return rec
end
end

function meta_object(name)
	return function (rec)
	rec = object(name)(rec)
	rec.is_package = true
	rec.is_meta = true
	return rec
end
end

function extends(name)
	return function (rec)
	rec = make_record(rec, "extends")
	-- base object name
	rec.name = name
	-- check for cast_type
	if rec.cast_type == nil then
		rec.cast_offset = 0
		rec.cast_type = 'direct'
	end
	return rec
end
end

function dyn_caster(rec)
	rec = make_record(rec, "dyn_caster")
	return rec
end

function option(name)
	return function (rec)
	rec = make_record(rec, "option")
	-- option name.
	rec.name = name
	return rec
end
end

function field(c_type)
	return function (name)
	return function (rec)
	local access = rec and rec[1] or nil
	rec = make_record(rec, "field")
	-- field's c_type
	rec.c_type = c_type
	-- field's name
	rec.name = name
	-- access permissions
	if type(access) == 'string' then
		access = access:lower()
		-- check for write access
		if access == 'rw' then
			rec.is_writable = true
		elseif access == 'ro' then
			rec.is_writable = false
		else
			rec.is_writable = false
		end
	elseif rec.is_writable == nil then
		rec.is_writable = false
	end
	return rec
end
end
end

function const(name)
	return function (rec)
	local value = rec[1]
	rec = make_record(rec, "const")
	-- field's name
	rec.name = name
	-- field's value
	rec.value = value
	return rec
end
end

function const_def(name)
	return function (rec)
	local value = rec[1]
	rec = make_record(rec, "const")
	-- this is a constant definition.
	rec.is_define = true
	-- default to 'number' type.
	rec.vtype = rec.vtype or 'number'
	-- field's name
	rec.name = name
	-- field's value
	rec.value = value
	return rec
end
end

function constants(values)
	rec = make_record({}, "constants")
	rec.values = values
	return rec
end

function export_definitions(values)
	if type(values) == 'string' then
		local name = values
		return function(values)
			return package(name)({
				map_constants_bidirectional = true,
				export_definitions(values)
			})
		end
	end
	rec = make_record({}, "export_definitions")
	rec.values = values
	return rec
end

function include(file)
	local rec = {}
	rec = make_record(rec, "include")
	rec.is_system = false
	rec.file = file
	return rec
end

function sys_include(file)
	local rec = {}
	rec = make_record(rec, "include")
	rec.is_system = true
	rec.file = file
	return rec
end

function c_function(name)
	return function (rec)
	rec = make_record(rec, "c_function")
	-- function name.
	rec.name = name
	-- function type (normal function or object method)
	rec.f_type = "function"
	-- variable lookup
	rec.get_var = function(self, name)
		for i=1,#self do
			local var = self[i]
			if is_record(var) and var.name == name then
				return var
			end
		end
		return nil
	end
	return rec
end
end

local meta_methods = {
__str__ = true,
__eq__ = true,
-- Lua metamethods
__add = true,
__sub = true,
__mul = true,
__div = true,
__mod = true,
__pow = true,
__unm = true,
__len = true,
__concat = true,
__eq = true,
__lt = true,
__le = true,
__gc = true,
__tostring = true,
__index = true,
__newindex = true,
}
function method(name)
	return function (rec)
	-- handle the same way as normal functions
	rec = c_function(name)(rec)
	-- mark this function as a method.
	rec._is_method = true
	-- if the method is a destructor, then also make it a meta method
	-- to be used for garbagecollection
	if rec.is_destructor then
		rec._is_meta_method = true
	end
	rec.f_type = "method"
	-- check if method is a meta-method.
	rec._is_meta_method = meta_methods[rec.name]
	return rec
end
end

function constructor(name)
	return function (rec)
	if type(name) == 'table' then rec = name; name = 'new' end
	-- handle the same way as normal method
	rec = method(name)(rec)
	-- mark this method as the constructor
	rec.is_constructor = true
	return rec
end
end

function destructor(name)
	return function (rec)
	if type(name) == 'table' then
		rec = name
		rec._is_hidden = true
		name = 'delete'
	end
	-- handle the same way as normal method
	rec = method(name)(rec)
	-- mark this method as the destructor
	rec.is_destructor = true
	-- also register it as a metamethod for garbagecollection.
	rec._is_meta_method = true
	return rec
end
end

function method_new(rec)
	return constructor(rec)
end

function method_delete(rec)
	return destructor(rec)
end

function define(name)
	return function(value)
	rec = make_record({}, "define")
	rec.name = name
	rec.value = value
	return rec
end
end

function c_source(part)
	return function(src)
	if src == nil then
		src = part
		part = nil
	end
	rec = make_record({}, "c_source")
	rec.part = part or "src"
	rec.src = src
	return rec
end
end

local function strip_variable_tokens(val, tokens)
	local prefix, val, postfix = val:match("^([!@&*(?#]*)([%w_ *]*)([@?)<>]*[0-9]*)")
	return prefix .. (tokens or '') .. postfix, val
end

local function clean_variable_type_name(vtype,vname)
	local tokens
	tokens, vtype = strip_variable_tokens(vtype)
	tokens, vname = strip_variable_tokens(vname)
	return vtype, vname
end

local function parse_variable_name(var)
	-- no parsing needed for '<any>'
	if var.c_type == '<any>' then return end
	-- strip tokens from variable name & c_type
	local tokens, name, c_type
	tokens, name = strip_variable_tokens(var.name)
	tokens, c_type = strip_variable_tokens(var.c_type, tokens)
	-- set variable name to stripped name
	var.name = name
	var.c_type = c_type
	-- parse prefix & postfix tokens
	local n=1
	local len = #tokens
	while n <= len do
		local tok = tokens:sub(n,n)
		n = n + 1
		if tok == '*' then
			assert(var.wrap == nil, "Variable already has a access wrapper.")
			var.wrap = '*'
		elseif tok == '&' then
			assert(var.wrap == nil, "Variable already has a access wrapper.")
			var.wrap = '&'
		elseif tok == '#' then
			var.is_length_ref = true
		elseif tok == '?' then
			var.is_optional = true
			-- eat the rest of the tokens as the default value.
			if n <= len then
				var.default = tokens:sub(n)
			end
			break
		elseif tok == '!' then
			var.own = true
		elseif tok == '@' then
			var.is_ref_field = true
			error("`@ref_name` not yet supported.")
		elseif tok == '<' or tok == '>' then
			local idx = tokens:match('([0-9]*)', n)
			assert(idx, "Variable already has a stack order 'idx'")
			var.idx = tonumber(idx)
			if tok == '>' then
				-- force this variable to an output type.
				var._rec_type = 'var_out'
			else
				assert(var._rec_type == 'var_in', "Can't make an output variable into an input variable.")
			end
			-- skip index value.
			if idx then n = n + #idx end
		elseif tok == '(' or tok == ')' then
			var._rec_type = 'var_out'
			var.is_temp = true
		end
	end
	-- do some validation.
	if var.own then
		assert(var._rec_type == 'var_out', "Only output variables can be marked as 'owned'.")
	end
end

function var_out(rec)
	rec = make_record(rec, "var_out")
	-- out variable's c_type
	rec.c_type = table.remove(rec, 1)
	-- out variable's name
	rec.name = table.remove(rec, 1)
	-- parse tags from name.
	parse_variable_name(rec)
	resolve_rec(rec)
	return rec
end

function var_in(rec)
	rec = make_record(rec, "var_in")
	-- in variable's c_type
	rec.c_type = table.remove(rec, 1)
	-- in variable's name
	rec.name = table.remove(rec, 1)
	-- parse tags from name.
	parse_variable_name(rec)
	resolve_rec(rec)
	return rec
end

-- A reference to another var_in/var_out variable.
-- This is used by `c_call` records.
function var_ref(var)
	local rec = {}
	-- copy details from var_* record
	for k,v in pairs(var) do rec[k] = v end
	-- make variable reference.
	rec = make_record(rec, "var_ref")
	-- in variable's c_type
	rec.c_type = var.c_type
	-- in variable's name
	rec.name = var.name
	resolve_rec(rec)
	return rec
end

function c_call(return_type)
	return function (cfunc)
	return function (params)
	local rec = make_record({}, "c_call")
	-- parse return c_type.
	rec.ret = return_type or "void"
	-- parse c function to call.
	rec.cfunc = cfunc
	-- parse params
	rec.params = params
	if rec.params == nil then rec.params = {} end
	return rec
end
end
end

function c_macro_call(ret)
	return function (cfunc)
	return function (params)
	local rec = c_call(ret)(cfunc)(params)
	rec.ffi_need_wrapper = "c_wrap"
	rec.is_macro_call = true
	return rec
end
end
end

function c_inline_call(ret)
	return function (cfunc)
	return function (params)
	local rec = c_call(ret)(cfunc)(params)
	rec.ffi_need_wrapper = "c_wrap"
	rec.is_inline_call = true
	return rec
end
end
end

function c_export_call(ret)
	return function (cfunc)
	return function (params)
	local rec = c_call(ret)(cfunc)(params)
	rec.ffi_need_wrapper = "c_export"
	rec.is_export_call = true
	return rec
end
end
end

function c_method_call(ret)
	return function (cfunc)
	return function (params)
	local rec = c_call(ret)(cfunc)(params)
	rec.is_method_call = true
	return rec
end
end
end

function c_export_method_call(ret)
	return function (cfunc)
	return function (params)
	local rec = c_method_call(ret)(cfunc)(params)
	rec.ffi_need_wrapper = "c_export"
	rec.is_export_call = true
	return rec
end
end
end

function c_macro_method_call(ret)
	return function (cfunc)
	return function (params)
	local rec = c_method_call(ret)(cfunc)(params)
	rec.ffi_need_wrapper = "c_wrap"
	rec.is_macro_call = true
	return rec
end
end
end

function callback_type(name)
	return function (return_type)
	return function (params)
	rec = make_record({}, "callback_type")
	rec.is_callback = true
	-- function type name.
	rec.name = name
	-- c_type for callback.
	rec.c_type = name
	-- parse return c_type.
	rec.ret = return_type or "void"
	-- parse params
	if params == nil then params = {} end
	rec.params = params
	-- add new types
	new_c_type(rec.c_type, rec)
	return rec
end
end
end

function callback(c_type)
	if type(c_type) == 'table' then
		local rec = var_in(c_type)
		rec.is_callback = true
		rec.is_ref = true
		rec.ref_field = rec.name
		-- other variable that will be wrapped to hold callback state information.
		rec.state_var = table.remove(rec, 1)
		return rec
	end
	return function (name)
	return function (state_var)
	return callback({c_type, name, state_var})
end
end
end

function callback_state(base_type)
	-- cleanup base_type
	base_type = base_type:gsub("[ *]","")
	-- create name for new state type
	name = base_type .. "_cb_state"
	-- make it an callback_state record.
	rec = make_record({}, "callback_state")
	-- the wrapper type
	rec.wrap_type = name
	-- base_type we are wrapping.
	rec.base_type = base_type
	-- c_type we are wrapping. (pointer to base_type)
	rec.c_type = name .. " *"
	-- resolve base_type
	rec.base_type_rec = resolve_c_type(rec.base_type)
	-- add new types
	new_c_type(rec.c_type, rec)
	return rec
end

function callback_func(c_type)
	return function (name)
	rec = make_record({}, "callback_func")
	rec.is_ref = true
	rec.ref_field = name
	-- c_type for callback.
	rec.c_type = c_type
	-- callback variable's name
	rec.name = name
	-- callback function name.
	rec.c_func_name = c_type .. "_" .. name .. "_cb"
	resolve_rec(rec)
	return rec
end
end

function cb_out(rec)
	rec = make_record(rec, "cb_out")
	-- out variable's c_type
	rec.c_type = table.remove(rec, 1)
	-- out variable's name
	rec.name = table.remove(rec, 1)
	resolve_rec(rec)
	return rec
end

function cb_in(rec)
	rec = make_record(rec, "cb_in")
	-- in variable's c_type
	rec.c_type = table.remove(rec, 1)
	-- in variable's name
	local name = table.remove(rec, 1)
	-- check if this is a wrapped object parameter.
	if name:sub(1,1) == '%' then
		rec.is_wrapped_obj = true;
		name = name:sub(2)
	end
	rec.name = name
	resolve_rec(rec)
	return rec
end

function c_module(name)
	return function (rec)
	rec = make_record(rec, "c_module")
	-- c_module name.
	rec.name = name
	return rec
end
end

function lang(name)
	return function (rec)
		rec.name = name
		rec = make_record(rec, "lang")
		-- only keep records for current language.
		if rec.name ~= gen_lang then
			-- delete this record and it sub-records
			rec:delete_record()
		end
		return rec
	end
end

function ffi(rec)
	return make_record(rec, "ffi")
end

function ffi_files(rec)
	for i=1,#rec do
		rec[i] = subfile_path(rec[i])
	end
	return make_record(rec, "ffi_files")
end

function ffi_source(part)
	return function(src)
	if src == nil then
		src = part
		part = nil
	end
	rec = make_record({}, "ffi_source")
	rec.part = part or "ffi_src"
	rec.src = src
	return rec
end
end

function ffi_typedef(cdef)
	return ffi_source("ffi_typedef")(cdef)
end

function ffi_cdef(cdef)
	return ffi_source("ffi_cdef")(cdef)
end

function ffi_load(name)
	if type(name) == 'table' then
		local default_lib = name[1] or name.default
		local src = { 'local os_lib_table = {\n' }
		local off = #src
		for k,v in pairs(name) do
			if type(k) == 'string' and type(v) == 'string' then
				off = off + 1; src[off] = '\t["'
				off = off + 1; src[off] = k
				off = off + 1; src[off] = '"] = "'
				off = off + 1; src[off] = v
				off = off + 1; src[off] = '",\n'
			end
		end
		off = off + 1; src[off] = '}\n'
		off = off + 1; src[off] = 'local C = ffi_load(os_lib_table[ffi.os]'
		if type(default_lib) == 'string' then
			off = off + 1; src[off] = ' or "'
			off = off + 1; src[off] = default_lib
			off = off + 1; src[off] = '"'
		end
		if name.global then
			off = off + 1; src[off] = ', true'
		end
		off = off + 1; src[off] = ')\n'
		return ffi_source("ffi_src")(tconcat(src))
	end
	return function (global)
		if global == nil then global = false end
		global = tostring(global)
		local src = 'local C = ffi_load("' .. name .. '",' .. global .. ')\n'
		return ffi_source("ffi_src")(src)
	end
end

function ffi_export(c_type)
	return function (name)
	rec = make_record({}, "ffi_export")
	-- parse c_type.
	rec.c_type = c_type
	-- parse name of symbol to export
	rec.name = name
	return rec
end
end

function ffi_export_function(return_type)
	return function (name)
	return function (params)
	rec = make_record({}, "ffi_export_function")
	-- parse return c_type.
	rec.ret = return_type or "void"
	-- parse c function to call.
	rec.name = name
	-- parse params
	rec.params = params
	if rec.params == nil then rec.params = {} end
	return rec
end
end
end

--
-- End records functions
--

local module_file = nil
local outpath = ""
local outfiles = {}
function get_outfile_name(ext)
	local filename = module_file .. ext
	return outpath .. filename
end
function open_outfile(ext)
	local filename = module_file .. ext
	local file = outfiles[filename]
	if file == nil then
		file = io.open(outpath .. filename, "w+")
		outfiles[filename] = file
	end
	return file
end
function close_outfiles()
	for name,file in pairs(outfiles) do
		io.close(file)
		outfiles[name] = nil
	end
end

local function process_module_file(file)
	-- clear root_records & c_types
	reset()

	module_file = file:gsub("(.lua)$","")
	print("module_file", module_file)
	print("Parsing records from file: " .. file)
	dofile(file)

	--
	-- run stage parsers
	--
	run_stage_parsers()

	--
	-- process some container records
	--
	process_records{
	lang = function(self, rec, parent)
		-- only keep records for current language.
		if rec.name == gen_lang then
			-- keep records by moving them up to the parent
			move_recs(parent, rec)
		else
			-- delete this record and it sub-records
			rec:delete_record()
		end
	end,
	object = function(self, rec, parent)
		-- re-map c_types
		new_c_type(rec.name, rec)
		new_c_type(rec.c_type, rec)
	end,
	ffi_files = function(self, rec, parent)
		for i=1,#rec do
			local file = assert(io.open(rec[i], "r"))
			parent:add_record(ffi_source(rec.part)(file:read("*a")))
			file:close()
		end
	end,
	constants = function(self, rec, parent)
		for key,value in pairs(rec.values) do
			parent:add_record(const(key)({ value }))
		end
		rec._rec_type = nil
	end,
	export_definitions = function(self, rec, parent)
		local values = rec.values
		-- export list of definitions as-is (i.e. no renaming).
		for i=1,#values do
			local name = values[i]
			parent:add_record(const_def(name)({ name }))
			values[i] = nil
		end
		-- export renamed definitions.
		for key, value in pairs(values) do
			parent:add_record(const_def(key)({ value }))
		end
		rec._rec_type = nil
	end,
	unknown = function(self, rec, parent)
		-- re-map c_types
		if rec._is_c_type ~= nil then
			new_c_type(rec.c_type, rec)
		end
	end,
	}

	--
	-- convert fields into get/set methods.
	--
	process_records{
	field = function(self, rec, parent)
		local name = rec.name
		local c_type = rec.c_type
		parent:add_record(method(name) {
			var_out{c_type , "field"},
			c_source 'src' {"\t${field} = ${this}->", name,";\n" },
		})
		if rec.is_writable then
			parent:add_record(method("set_" .. name) {
				var_in{c_type , "field"},
				c_source 'src' {"\t${this}->", name," = ${field};\n" },
			})
		end
	end,
	}

	--
	-- add 'this' variable to method records.
	--
	process_records{
	c_function = function(self, rec, parent)
		if rec._is_method and not rec.override_this then
			local var
			if parent.is_meta then
				var = var_in{ "<any>", "this", is_this = true }
			elseif rec.is_constructor then
				var = var_out{ parent.c_type, "this", is_this = true }
				-- make the first constructor the default.
				if not parent.default_constructor then
					parent.default_constructor = rec
					rec.is_default_constructor = true
				end
			else
				var = var_in{ parent.c_type, "this", is_this = true }
			end
			rec:insert_record(var, 1)
		end
	end,
	}

	--
	-- create callback_func & callback_state records.
	--
	process_records{
	var_in = function(self, rec, parent)
		-- is variable a callback type?
		if not rec.is_callback then return end
		-- get grand-parent container
		local container = parent._parent
		-- create callback_state instance.
		local cb_state
		if rec.state_var == 'this' then
			local wrap_type = container.c_type
			cb_state = callback_state(wrap_type)
			-- wrap 'this' object.
			container.is_wrapped = true
			container.wrapper_obj = cb_state
		else
			assert("un-supported callback state var: " .. rec.state_var)
		end
		container:insert_record(cb_state, 1)
		-- create callback_func instance.
		local cb_func = callback_func(rec.c_type)(rec.name)
		-- move sub-records from 'var_in' callback record into 'callback_func'
		local cb=rec
		for i=1,#cb do
			local rec = cb[i]
			if is_record(rec) and rec._rec_type ~= "ignore" then
				cb:remove_record(rec) -- remove from 'var_in'
				cb_func:add_record(rec) -- add to 'callback_func'
			end
		end
		cb_state:add_record(cb_func)
		rec.cb_func = cb_func
		rec.c_type_rec = cb_func
	end,
	}

	--
	-- process extends/dyn_caster records
	--
	process_records{
	_obj_cnt = 0,
	object = function(self, rec, parent)
		rec._obj_id = self._obj_cnt
		self._obj_cnt = self._obj_cnt + 1
	end,
	extends = function(self, rec, parent)
		-- find base-object record.
		local base = resolve_c_type(rec.name)
		rec.base = base
		-- add this object to base.
		local subs = base.subs
		if subs == nil then
			subs = {}
			base.subs = subs
		end
		subs[#subs+1] = parent
	end,
	dyn_caster = function(self, rec, parent)
		parent.has_dyn_caster = rec
		if rec.caster_type == 'switch' then
			for k,v in pairs(rec.value_map) do
				rec.value_map[k] = resolve_c_type(v)
			end
		end
	end,
	unknown = function(self, rec, parent)
		resolve_rec(rec)
	end,
	}

	--
	-- Create FFI-wrappers for inline/macro calls
	--
	local ffi_wrappers = {}
	process_records{
	c_call = function(self, rec, parent)
		if not rec.ffi_need_wrapper then
			-- normal C call don't need wrapper.
			return
		end
		-- find parent 'object' record.
		local object = parent
		while object._rec_type ~= 'object' and object._rec_type ~= 'c_module' do
			object = object._parent
			assert(object, "Can't find parent 'object' record of 'c_call'")
		end
		local ret_type = rec.ret
		local ret = ret_type
		-- convert return type into "var_out" if it's not a "void" type.
		if ret ~= "void" then
			if type(ret) ~= 'string' then
				ret_type = ret[1]
			end
			ret = "  return "
		else
			ret_type = "void"
			ret = "  "
		end
		-- build C call statement.
		local call = {}
		local cfunc_name = rec.cfunc
		call[#call+1] = ret
		call[#call+1] = cfunc_name
		-- process parameters.
		local params = {}
		local list = rec.params
		params[#params+1] = "("
		call[#call+1] = "("
		if rec.is_method_call then
			call[#call+1] = 'this'
			params[#params+1] = object.c_type .. ' '
			params[#params+1] = 'this'
			if #list > 0 then
				params[#params+1] = ", "
				call[#call+1] = ", "
			end
		end
		for i=1,#list,2 do
			local c_type,name = clean_variable_type_name(list[i], list[i+1])
			if i > 1 then
				params[#params+1] = ", "
				call[#call+1] = ", "
			end
			-- append parameter name
			call[#call+1] = name
			-- append parameter type & name to cdef
			params[#params+1] = c_type .. ' '
			params[#params+1] = name
		end
		params[#params+1] = ")"
		call[#call+1] = ");\n"
		-- convert 'params' to string.
		params = tconcat(params)
		call = tconcat(call)
		-- get prefix
		local export_prefix = ""
		if rec.ffi_need_wrapper == 'c_wrap' then
			export_prefix = "ffi_wrapper_"
		end
		rec.ffi_export_prefix = export_prefix
		-- check for re-definitions or duplicates.
		local cdef = ret_type .. " " .. export_prefix .. cfunc_name .. params
		local old_cdef = ffi_wrappers[cfunc_name]
		if old_cdef == cdef then
			return -- duplicate, don't need to create a new wrapper.
		elseif old_cdef then
			error("Re-definition of FFI wrapper cdef: " .. cdef)
		end
		ffi_wrappers[cfunc_name] = cdef
		-- create wrapper function
		if rec.ffi_need_wrapper == 'c_wrap' then
			object:add_record(c_source("src")({
			"\n/* FFI wrapper for inline/macro call */\n",
			"static ", cdef, " {\n",
			call,
			"}\n",
			}))
		end
		object:add_record(ffi_export_function(ret_type)(export_prefix .. rec.cfunc)(params))
	end,
	}

	--
	-- do some pre-processing of records.
	--
	local ffi_cdefs = {}
	process_records{
	c_module = function(self, rec, parent)
		rec.functions = {}
		rec.constants = {}
		rec.fields = {}
		rec.name_map = {}
	end,
	object = function(self, rec, parent)
		rec.functions = {}
		rec.constants = {}
		rec.fields = {}
		rec.name_map = {}
		rec.extends = {}
	end,
	callback_state = function(self, rec, parent)
		rec.callbacks = {}
	end,
	extends = function(self, rec, parent)
		-- add base-class to parent's base list.
		parent.extends[rec.name] = rec
	end,
	field = function(self, rec, parent)
		-- add to name map to reserve the name.
		assert(parent.name_map[rec.name] == nil)
		--parent.name_map[rec.name] = rec
		-- add field to parent's fields list.
		parent.fields[rec.name] = rec
	end,
	const = function(self, rec, parent)
		-- add to name map to reserve the name.
		assert(parent.name_map[rec.name] == nil)
		parent.name_map[rec.name] = rec
		-- add constant to parent's constants list.
		parent.constants[rec.name] = rec
	end,
	c_function = function(self, rec, parent)
		local c_name = parent.name .. '__' .. rec.name
		if rec._is_method then
			assert(not parent.is_package or parent.is_meta,
				"Package's can't have methods: package=" .. parent.name .. ", method=" .. rec.name)
			c_name = c_name .. '__meth'
		else
			c_name = c_name .. '__func'
		end
		rec.c_name = c_name
		-- add to name map to reserve the name.
		assert(parent.name_map[rec.name] == nil,
			"duplicate functions " .. rec.name .. " in " .. parent.name)
		parent.name_map[rec.name] = rec
		-- add function to parent's function list.
		parent.functions[rec.name] = rec
		-- prepare wrapped new/delete methods
		if rec._is_method and parent.is_wrapped then
			if rec.is_destructor or rec.is_constructor then
				rec.is_wrapper = true
				rec.wrapper_obj = parent.wrapper_obj
			end
		end
		-- map names to in/out variables
		rec.var_map = {}
		function rec:add_variable(var, name)
			name = name or var.name
			local old_var = self.var_map[name]
			assert(old_var == nil or old_var == var,
				"duplicate variable " .. name .. " in " .. self.name)
			-- add this variable to parent
			self.var_map[name] = var
		end
	end,
	callback_func = function(self, rec, parent)
		local func_type = rec.c_type_rec
		-- add callback to parent's callback list.
		parent.callbacks[rec.ref_field] = rec
		local src={"static "}
		local typedef={"typedef "}
		-- convert return type into "cb_out" if it's not a "void" type.
		local ret = func_type.ret
		if ret ~= "void" then
			rec.ret_out = cb_out{ ret, "ret" }
			rec:insert_record(rec.ret_out, 1)
		end
		src[#src+1] = ret .. " "
		typedef[#typedef+1] = ret .. " "
		-- append c function to call.
		rec.c_func_name = parent.base_type .. "_".. rec.ref_field .. "_cb"
		src[#src+1] = rec.c_func_name .. "("
		typedef[#typedef+1] = "(*" .. rec.c_type .. ")("
		-- convert params to "cb_in" records.
		local params = func_type.params
		local vars = {}
		for i=1,#params,2 do
			local c_type = params[i]
			local name = params[i + 1]
			if i > 1 then
				src[#src+1] = ", "
				typedef[#typedef+1] = ", "
			end
			-- add cb_in to this rec.
			local v_in = cb_in{ c_type, name}
			rec:insert_record(v_in, 1)
			src[#src+1] = c_type .. " ${" .. v_in.name .. "}"
			typedef[#typedef+1] = c_type .. " " .. v_in.name
			vars[#vars+1] = "${" .. v_in.name .. "}"
		end
		src[#src+1] = ")"
		typedef[#typedef+1] = ");"
		-- save callback func decl.
		rec.c_func_decl = table.concat(src)
		rec.c_func_typedef = table.concat(typedef)
		rec.param_vars = table.concat(vars, ', ')
		-- map names to in/out variables
		rec.var_map = {}
		function rec:add_variable(var, name)
			name = name or var.name
			local old_var = self.var_map[name]
			assert(old_var == nil or old_var == var,
				"duplicate variable " .. name .. " in " .. self.name)
			-- add this variable to parent
			self.var_map[name] = var
		end
	end,
	var_in = function(self, rec, parent)
		parent:add_variable(rec)
	end,
	var_out = function(self, rec, parent)
		parent:add_variable(rec)
	end,
	cb_in = function(self, rec, parent)
		parent:add_variable(rec)
	end,
	cb_out = function(self, rec, parent)
		parent:add_variable(rec)
	end,
	c_call = function(self, rec, parent)
		local src={}
		local ffi_cdef={}
		local ffi_src={}
		local ret_type = rec.ret
		local ret = ret_type
		-- convert return type into "var_out" if it's not a "void" type.
		if ret ~= "void" then
			local is_this = false
			-- check if return value is for the "this" value in a constructor.
			if parent.is_constructor then
				local this_var = parent.var_map.this
				if this_var and ret == this_var.c_type then
					ret_type = this_var.c_type
					is_this = true
				end
			end
			if is_this then
				ret = "  ${this} = "
			else
				local rc
				if type(ret) == 'string' then
					rc = var_out{ ret, "rc_" .. rec.cfunc }
				else
					rc = var_out(ret)
				end
				ret_type = rc.c_type
				if rc.is_length_ref then
					ret = "  ${" .. rc.name .. "_len} = "
					-- look for related 'var_out'.
					local rc_val = parent.var_map[rc.name]
					if rc_val then
						rc_val.has_length = true
					else
						-- related 'var_out' not processed yet.
						-- add place-holder
						parent.var_map[rc.name] = rc
					end
				else
					ret = "  ${" .. rc.name .. "} = "
					-- look for related length reference.
					local rc_len = parent.var_map[rc.name]
					if rc_len and rc_len.is_length_ref then
						-- we have a length.
						rc.has_length = true
						-- remove length var place-holder
						parent.var_map[rc.name] = nil
					end
					-- register var_out variable.
					parent:add_variable(rc)
					-- add var_out record to parent
					parent:add_record(rc)
				end
				-- check for dereference.
				if rc.wrap == '*' then
					ret = ret .. '*'
				end
			end
		else
			ret = "  "
		end
		src[#src+1] = ret
		ffi_cdef[#ffi_cdef+1] = ret_type .. " "
		ffi_src[#ffi_src+1] = ret
		-- append c function to call.
		local func_start = rec.cfunc .. "("
		src[#src+1] = func_start
		ffi_cdef[#ffi_cdef+1] = func_start
		if rec.ffi_need_wrapper then
			ffi_src[#ffi_src+1] = rec.ffi_export_prefix
		else
			ffi_src[#ffi_src+1] = "C."
		end
		ffi_src[#ffi_src+1] = func_start
		-- convert params to "var_in" records.
		local params = {}
		local list = rec.params
		-- check if this `c_call` is a method call
		if rec.is_method_call then
			-- then add `this` parameter to call.
			local this = parent.var_map.this
			assert(this, "Missing `this` variable for method_call: " .. rec.cfunc)
			this = var_ref(this)
			parent:add_record(this)
			params[1] = this
		end
		for i=1,#list,2 do
			local c_type = list[i]
			local name = list[i+1]
			local param = var_in{ c_type, name}
			name = param.name
			-- check if this is a new input variable.
			if not parent.var_map[name] then
				-- add param as a variable.
				parent:add_variable(param)
			else
				-- variable exists, return this input variable into a reference.
				local ref = var_ref(param)
				-- invalidate old `var_in` record
				param._rec_type = nil
				param = ref
			end
			-- add param rec to parent.
			parent:add_record(param)
			params[#params + 1] = param
		end
		-- append all input variables to "c_source"
		for i=1,#params do
			local var = params[i]
			if i > 1 then
				src[#src+1] = ", "
				ffi_cdef[#ffi_cdef+1] = ", "
				ffi_src[#ffi_src+1] = ", "
			end
			local name = var.name
			if var.is_length_ref then
				name = "${" .. name .. "_len}"
			else
				name = "${" .. name .. "}"
			end
			-- append parameter to c source call
			if var.wrap then
				src[#src+1] = var.wrap .. "("
				src[#src+1] = name .. ")"
			else
				src[#src+1] = name
			end
			-- append parameter to ffi source call
			ffi_src[#ffi_src+1] = name
			-- append parameter type & name to ffi cdef record
			ffi_cdef[#ffi_cdef+1] = var.c_type
			if var.wrap == '&' then
				ffi_cdef[#ffi_cdef+1] = '*'
			end
		end
		src[#src+1] = ");"
		ffi_cdef[#ffi_cdef+1] = ");\n"
		ffi_src[#ffi_src+1] = ")"
		-- replace `c_call` with `c_source` record
		local idx = parent:replace_record(rec, c_source("src")(src))
		-- convert to string.
		ffi_cdef = tconcat(ffi_cdef)
		-- check for ffi cdefs re-definitions
		local cfunc = rec.cfunc
		local cdef = ffi_cdefs[cfunc]
		if cdef and cdef ~= ffi_cdef then
			local old_name = cfunc
			local i = 0
			-- search for next "free" alias name.
			repeat
				i = i + 1
				cfunc = old_name .. i
				cdef = ffi_cdefs[cfunc]
				-- search until "free" alias name, or same definition.
			until not cdef or cdef == ffi_cdef
			-- update ffi src with new alias name.
			ffi_src = tconcat(ffi_src)
			ffi_src = ffi_src:gsub(old_name .. '%(', cfunc .. '(')
			-- create a cdef "asm" alias.
			if not cdef then
				ffi_cdef = ffi_cdef:gsub(old_name, cfunc)
				ffi_cdef = ffi_cdef:gsub("%);\n$", [[) asm("]] .. old_name .. [[");]])
			end
		end
		ffi_cdefs[cfunc] = ffi_cdef
		-- insert FFI source record.
		if not cdef then
			-- function not defined yet.
			parent:insert_record(ffi_source("ffi_cdef")(ffi_cdef), idx)
		end
		parent:insert_record(ffi_source("ffi_src")(ffi_src), idx+1)
	end,
	ffi_export = function(self, rec, parent)
		local ffi_src={}
		-- load exported symbol
		ffi_src[#ffi_src+1] = 'local '
		ffi_src[#ffi_src+1] = rec.name
		ffi_src[#ffi_src+1] = ' = ffi.new("'
		ffi_src[#ffi_src+1] = rec.c_type
		ffi_src[#ffi_src+1] = ' *", _priv["'
		ffi_src[#ffi_src+1] = rec.name
		ffi_src[#ffi_src+1] = '"])\n'
		-- insert FFI source record.
		local idx = parent:find_record(rec)
		parent:insert_record(ffi_source("ffi_import")(ffi_src), idx)
	end,
	ffi_export_function = function(self, rec, parent)
		local ffi_cdef={}
		local ffi_src={}
		local cdef_name = rec.name .. '_func'
		-- pass C definition to FFI
		ffi_cdef[#ffi_cdef+1] = 'typedef '
		ffi_cdef[#ffi_cdef+1] = rec.ret .. " (*"
		ffi_cdef[#ffi_cdef+1] = cdef_name .. ")"
		local params = rec.params
		if type(params) == 'string' then
			ffi_cdef[#ffi_cdef+1] = params .. ";\n"
		else
			ffi_cdef[#ffi_cdef+1] = "("
			for i=1,#params,2 do
				local c_type = params[i]
				local name = params[i+1]
				if i > 1 then
					ffi_cdef[#ffi_cdef+1] = ","
				end
				ffi_cdef[#ffi_cdef+1] = c_type
			end
			ffi_cdef[#ffi_cdef+1] = ");\n"
		end
		-- load exported symbol
		ffi_src[#ffi_src+1] = 'local '
		ffi_src[#ffi_src+1] = rec.name
		ffi_src[#ffi_src+1] = ' = ffi.new("'
		ffi_src[#ffi_src+1] = rec.name
		ffi_src[#ffi_src+1] = '_func", _priv["'
		ffi_src[#ffi_src+1] = rec.name
		ffi_src[#ffi_src+1] = '"])\n'
		-- insert FFI source record.
		local idx = parent:find_record(rec)
		ffi_cdef = tconcat(ffi_cdef)
		parent:insert_record(ffi_source("ffi_cdef")(ffi_cdef), idx)
		parent:insert_record(ffi_source("ffi_import")(ffi_src), idx+1)
		-- check for duplicate ffi cdefs.
		local cdef = ffi_cdefs[cdef_name]
		if cdef and cdef ~= ffi_cdef then
			error("Re-definition of FFI cdef: " .. cdef)
		end
		ffi_cdefs[cdef_name] = ffi_cdef
	end,
	}
	-- clear ffi cdefs
	ffi_cdefs = nil

	--
	-- sort var_in/var_out records.
	--
	local function sort_vars(var1, var2)
		return (var1.idx < var2.idx)
	end
	process_records{
	c_function = function(self, rec, parent)
		local inputs = {}
		local in_count = 0
		local outputs = {}
		local out_count = 0
		local misc = {}
		local max_idx = #rec
		-- seperate sub-records
		for i=1,max_idx do
			local var = rec[i]
			local var_type = var._rec_type
			local sort = true
			local list
			if var_type == 'var_in' then
				list = inputs
				in_count = in_count + 1
			elseif var_type == 'var_out' then
				list = outputs
				out_count = out_count + 1
			else
				list = misc
				sort = false
			end
			if sort then
				local idx = var.idx
				if idx then
					-- force index of this variable.
					local old_var = list[idx]
					-- variable has a fixed
					list[idx] = var
					-- move old variable to next open slot
					var = old_var
				end
				-- place variable in next nil slot.
				if var then
					for i=1,max_idx do
						if not list[i] then
							-- done, found empty slot
							list[i] = var
							var = nil
							break
						end
					end
				end
				assert(var == nil, "Failed to find empty slot for variable.")
			else
				list[#list + 1] = var
			end
		end
		-- make sure there are no gaps between input/output variables.
		assert(#inputs == in_count,
			"Gaps between input variables, check your usage of `<idx` for function: " .. rec.name)
		assert(#outputs == out_count,
			"Gaps between output variables, check your usage of `>idx` for function: " .. rec.name)

		-- put sorted sub-records back into the `c_function` record.
		local idx=0
		for i=1,in_count do
			idx = idx + 1
			rec[idx] = inputs[i]
		end
		for i=1,out_count do
			idx = idx + 1
			rec[idx] = outputs[i]
		end
		for i=1,#misc do
			idx = idx + 1
			rec[idx] = misc[i]
		end
		-- generate list of input parameter names for FFI functions.
		local ffi_params = {}
		for i=1,in_count do
			local name = inputs[i].name
			if name ~= 'this' then
				ffi_params[i] = '${' .. inputs[i].name .. '}'
			else
				ffi_params[i] = 'self'
			end
		end
		rec.ffi_params = tconcat(ffi_params, ', ')
	end,
	}

	--
	-- load language module
	--
	require("native_objects.lang_" .. gen_lang)

	--
	-- mark functions which have an error_code var_out.
	--
	process_records{
	var_out = function(self, rec, parent)
		local var_type = rec.c_type_rec
		if var_type._is_error_code then
			assert(parent._has_error_code == nil,
				"A function/method can only have one var_out with type error_code.")
			-- mark the function as having an error code.
			parent._has_error_code = rec
		elseif var_type.error_on_null then
			-- if this variable is null then push a nil and error message.
			rec.is_error_on_null = true
		end
	end,
	}

	--
	-- load gen. module
	--
	print"============ generate api bindings ================="
	if gen_module ~= "null" then
		require("native_objects.gen_" .. gen_module)
	end

	close_outfiles()
end


--
-- parse command line options/files
--
local len=#arg
local i=1
while i <= len do
	local a=arg[i]
	local eat = 0
	i = i + 1
	if a:sub(1,1) ~= "-" then
		process_module_file(a)
	else
		if a == "-gen" then
			gen_module = arg[i]
			eat = 1
		elseif a == "-outpath" then
			outpath = arg[i]
			if outpath:sub(-1,-1) ~= "/" then
				outpath = outpath .. "/"
			end
			eat = 1
		elseif a == "-lang" then
			gen_lang = arg[i]
			eat = 1
		else
			print("Unkown option: " .. a)
		end
	end
	i = i + eat
end

