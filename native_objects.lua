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

-- add path of native_objects.lua to package.path
local native_objects_path=(arg[0]):gsub("native_objects.lua", "?.lua;")
package.path = package.path .. native_objects_path

require("record")

local tconcat=table.concat
local tremove=table.remove
local assert=assert
local error=error
local type=type
local io=io
local print=print
local pairs=pairs
local dofile=dofile
local tostring=tostring
local require=require

--
-- Switch language we are generating bindings for.
--
gen_lang="lua"

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
	c_type = strip_c_type(c_type)
	local old = c_types[c_type]
	if old and old ~= rec then
		print("WARNING changing c_type:", c_type, "from:", old, "to:", rec)
	end
	c_types[c_type] = rec
end

local function real_c_type_resolver(self)
	local c_type = self._c_type
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
		print("type not resolved yet: " .. self._c_type)
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
		print("type not resolved yet: " .. self._c_type)
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
		error("type not resolved yet: " .. self._c_type)
	end
end,
__eq = function(op1, op2)
	return op1._c_type == op2._c_type
end,
}
local cache_resolvers={}
function resolve_c_type(c_type)
	local c_type = strip_c_type(c_type)
	local resolver = cache_resolvers[c_type]
	if resolver == nil then
		resolver = {_c_type = c_type}
		setmetatable(resolver, resolve_meta)
		cache_resolvers[c_type] = resolver
	end
	return resolver
end

function resolve_rec(rec)
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
	local rec = ctype(name,{},"basetype")
	-- lang type
	rec.lang_type = lang_type
	-- default value
	rec.default = default
	return rec
end
end
end

function doc(text)
	return make_record({ text = text }, 'doc')
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
	local userdata_type = rec.userdata_type or 'generic'
	rec.userdata_type = userdata_type
	rec.has_obj_flags = true
	if userdata_type == 'generic' or userdata_type == 'embed' or userdata_type == 'simple ptr' then
		ctype(name .. " *", rec,"object")
		rec.is_ptr = true
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
	local rec = make_record({}, "constants")
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
	local rec = make_record({}, "export_definitions")
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
	local rec = make_record({}, "define")
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
	local rec = make_record({}, "c_source")
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
	rec.c_type = tremove(rec, 1)
	-- out variable's name
	rec.name = tremove(rec, 1)
	-- parse tags from name.
	parse_variable_name(rec)
	resolve_rec(rec)
	return rec
end

function var_in(rec)
	rec = make_record(rec, "var_in")
	-- in variable's c_type
	rec.c_type = tremove(rec, 1)
	-- in variable's name
	rec.name = tremove(rec, 1)
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
	local rec = make_record({}, "callback_type")
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
		rec.state_var = tremove(rec, 1)
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
	local name = base_type .. "_cb_state"
	-- make it an callback_state record.
	local rec = make_record({}, "callback_state")
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
	local rec = make_record({}, "callback_func")
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
	rec.c_type = tremove(rec, 1)
	-- out variable's name
	rec.name = tremove(rec, 1)
	resolve_rec(rec)
	return rec
end

function cb_in(rec)
	rec = make_record(rec, "cb_in")
	-- in variable's c_type
	rec.c_type = tremove(rec, 1)
	-- in variable's name
	local name = tremove(rec, 1)
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
	local rec = make_record({}, "ffi_source")
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
		off = off + 1; src[off] = 'C = ffi_load(os_lib_table[ffi.os]'
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
		local src = 'C = ffi_load("' .. name .. '",' .. global .. ')\n'
		return ffi_source("ffi_src")(src)
	end
end

function ffi_export(c_type)
	return function (name)
	local rec = make_record({}, "ffi_export")
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
	local rec = make_record({}, "ffi_export_function")
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
function open_outfile(filename, ext)
	local filename = (filename or module_file) .. (ext or '')
	local file = outfiles[filename]
	if file == nil then
		file = assert(io.open(outpath .. filename, "w+"))
		outfiles[filename] = file
	end
	return file
end
function get_outpath(path)
	return (outpath or './') .. (path or '')
end
function close_outfiles()
	for name,file in pairs(outfiles) do
		io.close(file)
		outfiles[name] = nil
	end
end

require("native_objects.stages")

local function process_module_file(file)
	-- clear root_records & c_types
	reset()

	--
	-- load language module
	--
	require("native_objects.lang_" .. gen_lang)

	module_file = file:gsub("(.lua)$","")
	print("module_file", module_file)
	print("Parsing records from file: " .. file)
	dofile(file)

	--
	-- run stage parsers
	--
	run_stage_parsers()

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

