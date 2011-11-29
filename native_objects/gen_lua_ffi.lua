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
-- build LuaJIT FFI bindings
--

local ffi_helper_types = [[
#if LUAJIT_FFI
typedef struct ffi_export_symbol {
	const char *name;
	void       *sym;
} ffi_export_symbol;
#endif
]]

local objHelperFunc = [[
#if LUAJIT_FFI
static int nobj_udata_new_ffi(lua_State *L) {
	size_t size = luaL_checkinteger(L, 1);
	luaL_checktype(L, 2, LUA_TTABLE);
	lua_settop(L, 2);
	/* create userdata. */
	lua_newuserdata(L, size);
	lua_replace(L, 1);
	/* set userdata's metatable. */
	lua_setmetatable(L, 1);
	return 1;
}

static const char nobj_ffi_support_key[] = "LuaNativeObject_FFI_SUPPORT";
static const char nobj_check_ffi_support_code[] =
"local stat, ffi=pcall(require,\"ffi\")\n" /* try loading LuaJIT`s FFI module. */
"if not stat then return false end\n"
"return true\n";

static int nobj_check_ffi_support(lua_State *L) {
	int rc;
	int err;

	/* check if ffi test has already been done. */
	lua_pushstring(L, nobj_ffi_support_key);
	lua_rawget(L, LUA_REGISTRYINDEX);
	if(!lua_isnil(L, -1)) {
		rc = lua_toboolean(L, -1);
		lua_pop(L, 1);
		return rc; /* return results of previous check. */
	}
	lua_pop(L, 1); /* pop nil. */

	err = luaL_loadbuffer(L, nobj_check_ffi_support_code,
		sizeof(nobj_check_ffi_support_code) - 1, nobj_ffi_support_key);
	if(0 == err) {
		err = lua_pcall(L, 0, 1, 0);
	}
	if(err) {
		const char *msg = "<err not a string>";
		if(lua_isstring(L, -1)) {
			msg = lua_tostring(L, -1);
		}
		printf("Error when checking for FFI-support: %s\n", msg);
		lua_pop(L, 1); /* pop error message. */
		return 0;
	}
	/* check results of test. */
	rc = lua_toboolean(L, -1);
	lua_pop(L, 1); /* pop results. */
		/* cache results. */
	lua_pushstring(L, nobj_ffi_support_key);
	lua_pushboolean(L, rc);
	lua_rawset(L, LUA_REGISTRYINDEX);
	return rc;
}

static int nobj_try_loading_ffi(lua_State *L, const char *ffi_mod_name,
		const char *ffi_init_code, const ffi_export_symbol *ffi_exports, int priv_table)
{
	int err;

	/* export symbols to priv_table. */
	while(ffi_exports->name != NULL) {
		lua_pushstring(L, ffi_exports->name);
		lua_pushlightuserdata(L, ffi_exports->sym);
		lua_settable(L, priv_table);
		ffi_exports++;
	}
	err = luaL_loadbuffer(L, ffi_init_code, strlen(ffi_init_code), ffi_mod_name);
	if(0 == err) {
		lua_pushvalue(L, -2); /* dup C module's table. */
		lua_pushvalue(L, priv_table); /* move priv_table to top of stack. */
		lua_remove(L, priv_table);
		lua_pushcfunction(L, nobj_udata_new_ffi);
		err = lua_pcall(L, 3, 0, 0);
	}
	if(err) {
		const char *msg = "<err not a string>";
		if(lua_isstring(L, -1)) {
			msg = lua_tostring(L, -1);
		}
		printf("Failed to install FFI-based bindings: %s\n", msg);
		lua_pop(L, 1); /* pop error message. */
	}
	return err;
}
#endif
]]

local module_init_src = [[
#if LUAJIT_FFI
	if(nobj_check_ffi_support(L)) {
		nobj_try_loading_ffi(L, "${module_c_name}", ${module_c_name}_ffi_lua_code,
			${module_c_name}_ffi_export, priv_table);
	}
#endif
]]

local submodule_init_src = [[
#if ${module_c_name}_${object_name}_LUAJIT_FFI
	if(nobj_check_ffi_support(L)) {
		nobj_try_loading_ffi(L, "${module_c_name}_${object_name}",
			${module_c_name}_${object_name}_ffi_lua_code,
			${module_c_name}_${object_name}_ffi_export, priv_table);
	}
#endif
]]

--
-- FFI templates
--
local ffi_helper_code = [===[
local ffi=require"ffi"
local function ffi_safe_load(name, global)
	local stat, C = pcall(ffi.load, name, global)
	if not stat then return nil, C end
	return C
end

local error = error
local type = type
local tonumber = tonumber
local tostring = tostring
local rawset = rawset
local p_config = package.config
local p_cpath = package.cpath

local function ffi_load_cmodule(name)
	local dir_sep = p_config:sub(1,1)
	local path_sep = p_config:sub(3,3)
	local path_mark = p_config:sub(5,5)
	local path_match = "([^" .. path_sep .. "]*)" .. path_sep
	-- convert dotted name to directory path.
	name = name:gsub('%.', dir_sep)
	-- try each path in search path.
	for path in p_cpath:gmatch(path_match) do
		local fname = path:gsub(path_mark, name)
		local C, err = ffi_safe_load(fname)
		-- return opened library
		if C then return C end
	end
	return nil, "Failed to find: " .. name
end

local _M, _priv, udata_new = ...

local band = bit.band
local d_getmetatable = debug.getmetatable
local d_setmetatable = debug.setmetatable

local OBJ_UDATA_FLAG_OWN		= 1
local OBJ_UDATA_FLAG_LOOKUP	= 2
local OBJ_UDATA_LAST_FLAG		= OBJ_UDATA_FLAG_LOOKUP

local OBJ_TYPE_FLAG_WEAK_REF	= 1
local OBJ_TYPE_SIMPLE					= 2

local function ffi_safe_cdef(block_name, cdefs)
	local fake_type = "struct sentinel_" .. block_name .. "_ty"
	local stat, size = pcall(ffi.sizeof, fake_type)
	if stat and size > 0 then
		-- already loaded this cdef block
		return
	end
	cdefs = fake_type .. "{ int a; int b; int c; };" .. cdefs
	return ffi.cdef(cdefs)
end

ffi_safe_cdef("LuaNativeObjects", [[

typedef struct obj_type obj_type;

typedef void (*base_caster_t)(void **obj);

typedef void (*dyn_caster_t)(void **obj, obj_type **type);

struct obj_type {
	dyn_caster_t    dcaster;  /**< caster to support casting to sub-objects. */
	int32_t         id;       /**< type's id. */
	uint32_t        flags;    /**< type's flags (weak refs) */
	const char      *name;    /**< type's object name. */
};

typedef struct obj_base {
	int32_t        id;
	base_caster_t  bcaster;
} obj_base;

typedef struct obj_udata {
	void     *obj;
	uint32_t flags;  /**< lua_own:1bit */
} obj_udata;

int memcmp(const void *s1, const void *s2, size_t n);

]])

-- cache mapping of cdata to userdata
local weak_objects = setmetatable({}, { __mode = "v" })

local function obj_udata_luacheck_internal(obj, type_mt, not_delete)
	local obj_mt = d_getmetatable(obj)
	if obj_mt == type_mt then
		-- convert userdata to cdata.
		return ffi.cast("obj_udata *", obj)
	end
	if not_delete then
		error("(expected `" .. type_mt['.name'] .. "`, got " .. type(obj) .. ")", 3)
	end
end

local function obj_udata_luacheck(obj, type_mt)
	local ud = obj_udata_luacheck_internal(obj, type_mt, true)
	return ud.obj
end

local function obj_udata_to_cdata(objects, ud_obj, c_type, ud_mt)
	-- convert userdata to cdata.
	local c_obj = ffi.cast(c_type, obj_udata_luacheck(ud_obj, ud_mt))
	-- cache converted cdata
	rawset(objects, ud_obj, c_obj)
	return c_obj
end

local function obj_udata_luadelete(ud_obj, type_mt)
	local ud = obj_udata_luacheck_internal(ud_obj, type_mt, false)
	if not ud then return nil, 0 end
	local obj, flags = ud.obj, ud.flags
	-- null userdata.
	ud.obj = nil
	ud.flags = 0
	-- invalid userdata, by setting the metatable to nil.
	d_setmetatable(ud_obj, nil)
	return obj, flags
end

local function obj_udata_luapush(obj, type_mt, obj_type, flags)
	if obj == nil then return end

	-- apply type's dynamic caster.
	if obj_type.dcaster ~= nil then
		local obj_ptr = ffi.new("void *[1]", obj)
		local type_ptr = ffi.new("obj_type *[1]", obj_type)
		obj_type.dcaster(obj_ptr, type_ptr)
		obj = obj_ptr[1]
		type = type_ptr[1]
	end

	-- create new userdata
	local ud_obj = udata_new(ffi.sizeof"obj_udata", type_mt)
	local ud = ffi.cast("obj_udata *", ud_obj)
	-- init. object
	ud.obj = obj
	ud.flags = flags

	return ud_obj
end

local function obj_udata_luadelete_weak(ud_obj, type_mt)
	local ud = obj_udata_luacheck_internal(ud_obj, type_mt, false)
	if not ud then return nil, 0 end
	local obj, flags = ud.obj, ud.flags
	-- null userdata.
	ud.obj = nil
	ud.flags = 0
	-- invalid userdata, by setting the metatable to nil.
	d_setmetatable(ud_obj, nil)
	-- remove object from weak ref. table.
	local obj_key = tonumber(ffi.cast('uintptr_t', obj))
	weak_objects[obj_key] = nil
	return obj, flags
end

local function obj_udata_luapush_weak(obj, type_mt, obj_type, flags)
	if obj == nil then return end

	-- apply type's dynamic caster.
	if obj_type.dcaster ~= nil then
		local obj_ptr = ffi.new("void *[1]", obj)
		local type_ptr = ffi.new("obj_type *[1]", obj_type)
		obj_type.dcaster(obj_ptr, type_ptr)
		obj = obj_ptr[1]
		type = type_ptr[1]
	end

	-- lookup object in weak ref. table.
	local obj_key = tonumber(ffi.cast('uintptr_t', obj))
	local ud_obj = weak_objects[obj_key]
	if ud_obj ~= nil then return ud_obj end

	-- create new userdata
	ud_obj = udata_new(ffi.sizeof"obj_udata", type_mt)
	local ud = ffi.cast("obj_udata *", ud_obj)
	-- init. object
	ud.obj = obj
	ud.flags = flags

	-- cache weak reference to object.
	weak_objects[obj_key] = ud_obj

	return ud_obj
end

local function obj_simple_udata_luacheck(ud_obj, type_mt)
	local obj_mt = d_getmetatable(ud_obj)
	if obj_mt == type_mt then
		-- convert userdata to cdata.
		return ffi.cast("void *", ud_obj)
	end
	error("(expected `" .. type_mt['.name'] .. "`, got " .. type(ud_obj) .. ")", 3)
end

local function obj_simple_udata_to_cdata(objects, ud_obj, c_type, ud_mt)
	-- convert userdata to cdata.
	local c_obj = ffi.cast(c_type, obj_simple_udata_luacheck(ud_obj, ud_mt))[0]
	-- cache converted cdata
	rawset(objects, ud_obj, c_obj)
	return c_obj
end

local function obj_embed_udata_to_cdata(objects, ud_obj, c_type, ud_mt)
	-- convert userdata to cdata.
	local c_obj = ffi.cast(c_type, obj_simple_udata_luacheck(ud_obj, ud_mt))
	-- cache converted cdata
	rawset(objects, ud_obj, c_obj)
	return c_obj
end

local function obj_simple_udata_luadelete(ud_obj, type_mt)
	-- invalid userdata, by setting the metatable to nil.
	d_setmetatable(ud_obj, nil)
end

local function obj_simple_udata_luapush(c_obj, size, type_mt)
	if c_obj == nil then return end

	-- create new userdata
	local ud_obj = udata_new(size, type_mt)
	local cdata = ffi.cast("void *", ud_obj)
	-- init. object
	ffi.copy(cdata, c_obj, size)

	return ud_obj, cdata
end

]===]

-- templates for typed *_check/*_delete/*_push functions
local ffi_obj_type_check_delete_push = {
['simple'] = [[
local obj_type_${object_name}_check
local obj_type_${object_name}_delete
local obj_type_${object_name}_push

do
local ${object_name}_mt = _priv.${object_name}
ffi_safe_cdef("${object_name}_simple_wrapper", [=[
struct ${object_name}_t {
	${object_name} _wrapped_val;
};
typedef struct ${object_name}_t ${object_name}_t;
]=])
local ${object_name}_sizeof = ffi.sizeof"${object_name}_t"

function obj_type_${object_name}_check(wrap_obj)
	return wrap_obj._wrapped_val
end

function obj_type_${object_name}_delete(wrap_obj)
	local this = wrap_obj._wrapped_val
	ffi.fill(wrap_obj, ${object_name}_sizeof, 0)
	return this
end

function obj_type_${object_name}_push(this)
	local wrap_obj = ffi.new("${object_name}_t")
	wrap_obj._wrapped_val = this
	return wrap_obj
end

function ${object_name}_mt:__tostring()
	return "${object_name}: " .. tostring(self._wrapped_val)
end
function ${object_name}_mt.__eq(val1, val2)
	if not ffi.istype("${object_name}_t", val2) then return false end
	return (val1._wrapped_val == val2._wrapped_val)
end

end

]],
['embed'] = [[
local obj_type_${object_name}_check
local obj_type_${object_name}_delete
local obj_type_${object_name}_push

do
local ${object_name}_mt = _priv.${object_name}
local ${object_name}_sizeof = ffi.sizeof"${object_name}"

function obj_type_${object_name}_check(obj)
	return obj
end

function obj_type_${object_name}_delete(obj)
	return obj
end

function obj_type_${object_name}_push(obj)
	return obj
end

function ${object_name}_mt:__tostring()
	return "${object_name}: " .. tostring(ffi.cast('void *', self))
end
function ${object_name}_mt.__eq(val1, val2)
	if not ffi.istype("${object_name}", val2) then return false end
	return (C.memcmp(val1, val2, ${object_name}_sizeof) == 0)
end

end

]],
['object id'] = [[
local obj_type_${object_name}_check
local obj_type_${object_name}_delete
local obj_type_${object_name}_push

do
local ${object_name}_mt = _priv.${object_name}
local ${object_name}_objects = setmetatable({}, { __mode = "k",
__index = function(objects, ud_obj)
	-- cdata object not in cache
	local c_obj = tonumber(ffi.cast('uintptr_t', obj_udata_luacheck(ud_obj, ${object_name}_mt)))
	c_obj = ffi.cast("${object_name} *", c_obj) -- cast from 'void *'
	rawset(objects, ud_obj, c_obj)
	return c_obj
end,
})
function obj_type_${object_name}_check(ud_obj)
	return ${object_name}_objects[ud_obj]
end

function obj_type_${object_name}_delete(ud_obj)
	local c_obj = ${object_name}_objects[ud_obj]
	${object_name}_objects[ud_obj] = nil
	local c_ptr, flags = obj_udata_luadelete(ud_obj, ${object_name}_mt)
	if c_obj == nil then
		c_obj = tonumber(ffi.cast('uintptr_t', c_ptr))
	end
	return c_obj, flags
end

local ${object_name}_type = ffi.cast("obj_type *", ${object_name}_mt[".type"])
function obj_type_${object_name}_push(c_obj, flags)
	local ud_obj = obj_udata_luapush(ffi.cast('void *', c_obj), ${object_name}_mt,
		${object_name}_type, flags)
	${object_name}_objects[ud_obj] = c_obj
	return ud_obj
end
end

]],
['generic'] = [[
local obj_type_${object_name}_check
local obj_type_${object_name}_delete
local obj_type_${object_name}_push

do
local ${object_name}_mt = _priv.${object_name}
local ${object_name}_objects = setmetatable({}, { __mode = "k",
__index = function(objects, ud_obj)
	return obj_udata_to_cdata(objects, ud_obj, "${object_name} *", ${object_name}_mt)
end,
})
function obj_type_${object_name}_check(ud_obj)
	return ${object_name}_objects[ud_obj]
end

function obj_type_${object_name}_delete(ud_obj)
	${object_name}_objects[ud_obj] = nil
	return obj_udata_luadelete(ud_obj, ${object_name}_mt)
end

local ${object_name}_type = ffi.cast("obj_type *", ${object_name}_mt[".type"])
function obj_type_${object_name}_push(c_obj, flags)
	local ud_obj = obj_udata_luapush(c_obj, ${object_name}_mt, ${object_name}_type, flags)
	${object_name}_objects[ud_obj] = c_obj
	return ud_obj
end
end

]],
['generic_weak'] = [[
local obj_type_${object_name}_check
local obj_type_${object_name}_delete
local obj_type_${object_name}_push

do
	local ${object_name}_mt = _priv.${object_name}
	ffi_safe_cdef("${object_name}_simple_wrapper", [=[
		struct ${object_name}_t {
			${object_name} *ptr;
			uint32_t       flags;
		};
		typedef struct ${object_name}_t ${object_name}_t;
	]=])
	local ${object_name}_objects = setmetatable({}, { __mode = "k",
	__index = function(objects, ud_obj)
		return obj_udata_to_cdata(objects, ud_obj, "${object_name} *", ${object_name}_mt)
	end,
	})
	function obj_type_${object_name}_check(obj)
		if ffi.istype("${object_name}_t", obj) then return obj.ptr end
		return ${object_name}_objects[obj]
	end

	function obj_type_${object_name}_delete(obj)
		if ffi.istype("${object_name}_t", obj) then
			local ptr, flags = obj.ptr, obj.flags
			obj.ptr = nil
			obj.flags = 0
			return ptr, flags
		end
		${object_name}_objects[obj] = nil
		return obj_udata_luadelete_weak(obj, ${object_name}_mt)
	end

	function obj_type_${object_name}_push(ptr, flags)
		local obj = ffi.new("${object_name}_t")
		obj.ptr = ptr
		obj.flags = flags or 0
		return obj
	end

	function ${object_name}_mt:__tostring()
		return "${object_name}: " .. tostring(self.ptr)
	end

	function ${object_name}_mt.__eq(val1, val2)
		if not ffi.istype("${object_name}_t", val2) then return false end
		return (val1.ptr == val2.ptr)
	end
end

]],
}

local ffi_obj_metatype = {
['simple'] = "${object_name}_t",
['embed'] = "${object_name}",
['object id'] = "${object_name}_t",
['generic'] = "${object_name}_t",
['generic_weak'] = "${object_name}_t",
}

-- module template
local ffi_module_template = [[
local _pub = {}
local _meth = {}
for obj_name,mt in pairs(_priv) do
	if type(mt) == 'table' and mt.__index then
		_meth[obj_name] = mt.__index
	end
end
_pub.${object_name} = _M
for obj_name,pub in pairs(_M) do
	_pub[obj_name] = pub
end

]]

local ffi_submodule_template = ffi_module_template

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

local function dump_lua_code_to_c_str(code)
	-- make Lua code C-safe
	code = code:gsub('[\n"\\%z]', {
	['\n'] = "\\n\"\n\"",
	['\r'] = "\\r",
	['"'] = [[\"]],
	['\\'] = [[\\]],
	['\0'] = [[\0]],
	})
	return '"' .. code .. '";'
end

local function reg_object_function(self, func, object)
	local ffi_table = '_meth'
	local name = func.name
	local reg_list
	-- check if this is object free/destructure method
	if func.is_destructor then
		if func._is_hidden then
			-- don't register '__gc' metamethods as a public object method.
			return '_priv', '__gc'
		else
			-- add '__gc' method.
			if not self._cur_module.disable__gc and not object.disable__gc then
				object:write_part('ffi_metas_regs',
					{'_priv.${object_name}.__gc = ', ffi_table,'.${object_name}.', func.c_name, '\n'})
			end
		end
	elseif func.is_constructor then
		ffi_table = '_pub'
	elseif func._is_meta_method then
		ffi_table = '_priv'
		-- use Lua's __* metamethod names
		name = lua_meta_methods[func.name]
	elseif func._is_method then
		ffi_table = '_meth'
	else
		ffi_table = '_pub'
	end
	return ffi_table, name
end

local function add_source(rec, part, src, pos)
	return rec:insert_record(c_source(part)(src), 1)
end

print"============ Lua bindings ================="
local parsed = process_records{
_modules_out = {},
_includes = {},

-- record handlers
c_module = function(self, rec, parent)
	local module_c_name = rec.name:gsub('(%.)','_')
	rec:add_var('module_c_name', module_c_name)
	rec:add_var('module_name', rec.name)
	rec:add_var('object_name', rec.name)
	self._cur_module = rec
	self._modules_out[rec.name] = rec
	add_source(rec, "typedefs", ffi_helper_types, 1)
	-- hide_meta_info?
	if rec.hide_meta_info == nil then rec.hide_meta_info = true end
	-- luajit_ffi?
	rec:insert_record(define("LUAJIT_FFI")(rec.luajit_ffi and 1 or 0), 1)
	-- luajit_ffi_load_cmodule?
	if rec.luajit_ffi_load_cmodule then
		rec:write_part("ffi_typedef", [[
-- Load C module
local C = assert(ffi_load_cmodule("${module_c_name}"))

]])
	end
	-- where we want the module function registered.
	rec.functions_regs = 'function_regs'
	rec.methods_regs = 'function_regs'
	-- symbols to export to FFI
	rec:write_part("ffi_export",
		{'static const ffi_export_symbol ${module_c_name}_ffi_export[] = {\n'})
	-- start two ffi.cdef code blocks (one for typedefs and one for function prototypes).
	rec:write_part("ffi_typedef", {
	'ffi.cdef[[\n'
	})
	rec:write_part("ffi_cdef", {
	'ffi.cdef[[\n'
	})
	-- add module's FFI template
	rec:write_part("ffi_obj_type", {
		ffi_module_template,
		'\n'
	})
end,
c_module_end = function(self, rec, parent)
	self._cur_module = nil
	-- end list of FFI symbols
	rec:write_part("ffi_export", {
	'  {NULL, NULL}\n',
	'};\n\n'
	})
	add_source(rec, "luaopen_defs", rec:dump_parts{ "ffi_export" }, 1)
	-- end ffi.cdef code blocks
	rec:write_part("ffi_typedef", {
	'\n]]\n\n'
	})
	rec:write_part("ffi_cdef", {
	'\n]]\n\n'
	})

	-- add module init code for FFI support
	local part = "module_init_src"
	rec:write_part(part, module_init_src)
	rec:vars_part(part)
	add_source(rec, part, rec:dump_parts(part))
	-- FFI helper C code.
	add_source(rec, "helper_funcs", objHelperFunc)
	-- encode luajit ffi code
	if rec.luajit_ffi then
		local ffi_code = ffi_helper_code .. rec:dump_parts{
			"ffi_typedef", "ffi_cdef", "ffi_obj_type", "ffi_import", "ffi_src",
			"ffi_metas_regs", "ffi_extends"
		}
		rec:write_part("ffi_code",
		{'\nstatic const char ${module_c_name}_ffi_lua_code[] = ', dump_lua_code_to_c_str(ffi_code)
		})
		rec:vars_part("ffi_code")
		add_source(rec, "extra_code", rec:dump_parts("ffi_code"))
	end
end,
error_code = function(self, rec, parent)
	rec:add_var('object_name', rec.name)
	rec:write_part("ffi_typedef", {
		'typedef ', rec.c_type, ' ', rec.name, ';\n\n',
	})
	-- add variable for error string
	rec:write_part("ffi_src", {
		'local function ',rec.func_name,'(err)\n',
		'  local err_str\n'
		})
end,
error_code_end = function(self, rec, parent)
	-- return error string.
	rec:write_part("ffi_src", [[
	return err_str
end

]])

	-- don't generate FFI bindings
	if self._cur_module.ffi_manual_bindings then return end

	-- copy generated FFI bindings to parent
	local ffi_parts = { "ffi_typedef", "ffi_cdef", "ffi_src" }
	rec:vars_parts(ffi_parts)
	parent:copy_parts(rec, ffi_parts)
end,
object = function(self, rec, parent)
	rec:add_var('object_name', rec.name)
	-- make luaL_reg arrays for this object
	if not rec.is_package then
		-- where we want the module function registered.
		rec.methods_regs = 'methods_regs'
		-- FFI typedef
		local ffi_type = rec.ffi_type or 'struct ${object_name}'
		rec:write_part("ffi_typedef", {
			'typedef ', ffi_type, ' ${object_name};\n',
		})
	elseif rec.is_meta then
		-- where we want the module function registered.
		rec.methods_regs = 'methods_regs'
	end
	rec.functions_regs = 'pub_funcs_regs'
	-- FFI code
	rec:write_part("ffi_src",
		{'\n-- Start "${object_name}" FFI interface\n'})
	-- Sub-module FFI code
	if rec.register_as_submodule then
		-- luajit_ffi?
		rec:write_part("defines",
			{'#define ${module_c_name}_${object_name}_LUAJIT_FFI ',(rec.luajit_ffi and 1 or 0),'\n'})
		-- symbols to export to FFI
		rec:write_part("ffi_export",
			{'\nstatic const ffi_export_symbol ${module_c_name}_${object_name}_ffi_export[] = {\n'})
		-- start two ffi.cdef code blocks (one for typedefs and one for function prototypes).
		rec:write_part("ffi_typedef", {
		'ffi.cdef[[\n'
		})
		rec:write_part("ffi_cdef", {
		'ffi.cdef[[\n'
		})
		-- add module's FFI template
		rec:write_part("ffi_obj_type", {
			ffi_submodule_template,
			'\n'
		})
	end
end,
object_end = function(self, rec, parent)
	-- check for dyn_caster
	local dyn_caster = 'NULL'
	if rec.has_dyn_caster then
		error("FFI-bindings doesn't support dynamic casters.")
		dyn_caster = rec.has_dyn_caster.dyn_caster_name
	end
	-- create check/delete/push macros
	local ud_type = rec.userdata_type
	if not rec.no_weak_ref then
		ud_type = ud_type .. '_weak'
	end
	if not rec.is_package then
		-- create FFI check/delete/push functions
		rec:write_part("ffi_obj_type", {
			rec.ffi_custom_check_delete_push or ffi_obj_type_check_delete_push[ud_type],
			'\n'
		})
	end
	-- register metatable for FFI cdata type.
	if not rec.is_package then
		local c_metatype = ffi_obj_metatype[ud_type]
		if c_metatype then
			rec:write_part("ffi_src",{
				'ffi.metatype("',c_metatype,'", _priv.${object_name})\n'})
		end
	end
	-- end object's FFI source
	rec:write_part("ffi_src",
		{'-- End "${object_name}" FFI interface\n\n'})

	if rec.register_as_submodule then
		if not (self._cur_module.luajit_ffi and rec.luajit_ffi) then
			return
		end
		-- Sub-module FFI code
		-- end list of FFI symbols
		rec:write_part("ffi_export", {
		'  {NULL, NULL}\n',
		'};\n\n'
		})
		-- end ffi.cdef code blocks
		rec:write_part("ffi_typedef", {
		'\n]]\n\n'
		})
		rec:write_part("ffi_cdef", {
		'\n]]\n\n'
		})
		local ffi_code = ffi_helper_code .. rec:dump_parts{
			"ffi_typedef", "ffi_cdef", "ffi_obj_type", "ffi_import", "ffi_src",
			"ffi_metas_regs", "ffi_extends"
		}
		rec:write_part("ffi_code",
		{'\nstatic const char ${module_c_name}_${object_name}_ffi_lua_code[] = ',
			dump_lua_code_to_c_str(ffi_code)
		})
		-- copy ffi_code to partent
		rec:vars_parts{ "ffi_code", "ffi_export" }
		parent:copy_parts(rec, { "ffi_code" })
		add_source(rec, "luaopen_defs", rec:dump_parts{ "ffi_export" }, 1)
		-- add module init code for FFI support
		local part = "module_init_src"
		rec:write_part(part, submodule_init_src)
		rec:vars_part(part)
		add_source(rec, part, rec:dump_parts(part))
	else
		-- apply variables to FFI parts
		local ffi_parts = { "ffi_obj_type", "ffi_export" }
		rec:vars_parts(ffi_parts)
		-- copy parts to parent
		parent:copy_parts(rec, ffi_parts)

		-- don't generate FFI bindings
		if self._cur_module.ffi_manual_bindings then return end

		-- copy generated FFI bindings to parent
		local ffi_parts = { "ffi_typedef", "ffi_cdef", "ffi_import", "ffi_src",
			"ffi_metas_regs", "ffi_extends"
		}
		rec:vars_parts(ffi_parts)
		parent:copy_parts(rec, ffi_parts)
	end

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
	local base_cast = 'NULL'
	if base == nil then return end
	-- add methods/fields/constants from base object
	parent:write_part("ffi_src",
		{'-- Clear out methods from base class, to allow ffi-based methods from base class\n'})
	parent:write_part("ffi_extends",
		{'-- Copy ffi methods from base class to sub class.\n'})
	for name,val in pairs(base.name_map) do
		-- make sure sub-class has not override name.
		if parent.name_map[name] == nil then
			parent.name_map[name] = val
			if val._is_method and not val.is_constructor then
				-- register base class's method with sub class
				local ffi_table, name = reg_object_function(self, val, parent)
				-- write ffi code to remove registered base class method.
				parent:write_part("ffi_src",
				{ffi_table,'.${object_name}.', name, ' = nil\n'})
				-- write ffi code to copy method from base class.
				parent:write_part("ffi_extends",
				{ffi_table,'.${object_name}.',name,' = ',
					ffi_table,'.',base.name,'.',name,'\n'})
			end
		end
	end
end,
extends_end = function(self, rec, parent)
end,
callback_func = function(self, rec, parent)
end,
callback_func_end = function(self, rec, parent)
end,
dyn_caster = function(self, rec, parent)
end,
dyn_caster_end = function(self, rec, parent)
end,
c_function = function(self, rec, parent)
	rec:add_var('object_name', parent.name)
	rec:add_var('function_name', rec.name)
	if rec.is_destructor then
		rec.__gc = true -- mark as '__gc' method
	end
	-- register method/function with object.
	local ffi_table, name = reg_object_function(self, rec, parent)

	-- generate FFI function
	rec:write_part("ffi_pre",
	{'-- method: ', name, '\n',
		'function ',ffi_table,'.${object_name}.', name, '(',rec.ffi_params,')\n'})
end,
c_function_end = function(self, rec, parent)
	-- don't generate FFI bindings
	if self._cur_module.ffi_manual_bindings then return end

	-- check if function has FFI support
	local ffi_src = rec:dump_parts("ffi_src")
	if rec.no_ffi or #ffi_src == 0 then return end

	-- end Lua code for FFI function
	local ffi_parts = {"ffi_temps", "ffi_pre", "ffi_src", "ffi_post"}
	local ffi_return = rec:dump_parts("ffi_return")
	-- trim last ', ' from list of return values.
	ffi_return = ffi_return:gsub(", $","")
	rec:write_part("ffi_post",
		{'  return ', ffi_return,'\n',
		 'end\n\n'})

	rec:vars_parts(ffi_parts)
	-- append FFI-based function to parent's FFI source
	local ffi_cdef = { "ffi_cdef" }
	rec:vars_parts(ffi_cdef)
	parent:write_part("ffi_cdef", rec:dump_parts(ffi_cdef))
	parent:write_part("ffi_src", rec:dump_parts(ffi_parts))
end,
c_source = function(self, rec, parent)
end,
ffi_export = function(self, rec, parent)
	parent:write_part("ffi_export",
		{'{ "', rec.name, '", ', rec.name, ' },\n'})
end,
ffi_export_function = function(self, rec, parent)
	parent:write_part("ffi_export",
		{'{ "', rec.name, '", ', rec.name, ' },\n'})
end,
ffi_source = function(self, rec, parent)
	parent:write_part(rec.part, rec.src)
	parent:write_part(rec.part, "\n")
end,
var_in = function(self, rec, parent)
	-- no need to add code for 'lua_State *' parameters.
	if rec.c_type == 'lua_State *' and rec.name == 'L' then return end
	-- register variable for code gen (i.e. so ${var_name} is replaced with true variable name).
	parent:add_rec_var(rec)
	-- don't generate code for '<any>' type parameters
	if rec.c_type == '<any>' then return end

	local lua = rec.c_type_rec
	if rec.is_this and parent.__gc then
		if rec.has_obj_flags then
			-- add flags ${var_name_flags} variable
			parent:add_rec_var(rec, rec.name .. '_flags')
			-- for garbage collect method, check the ownership flag before freeing 'this' object.
			parent:write_part("ffi_pre",
				{
				'  ', lua:_ffi_delete(rec, true),
				'  if(band(${',rec.name,'_flags},OBJ_UDATA_FLAG_OWN) == 0) then return end\n',
				})
		else
			-- for garbage collect method, check the ownership flag before freeing 'this' object.
			parent:write_part("ffi_pre",
				{
				'  ', lua:_ffi_delete(rec, false),
				})
		end
	elseif lua._rec_type ~= 'callback_func' then
		if lua.lang_type == 'string' then
			-- add length ${var_name_len} variable
			parent:add_rec_var(rec, rec.name .. '_len')
		end
		-- check lua value matches type.
		local ffi_get
		if rec.is_optional then
			ffi_get = lua:_ffi_opt(rec, rec.default)
		else
			ffi_get = lua:_ffi_check(rec)
		end
		parent:write_part("ffi_pre",
			{'  ', ffi_get })
	end
end,
var_out = function(self, rec, parent)
	if rec.is_length_ref then
		return
	end
	local flags = false
	local lua = rec.c_type_rec
	if lua.has_obj_flags and (rec.is_this or rec.own) then
		-- add flags ${var_name_flags} variable
		parent:add_rec_var(rec, rec.name .. '_flags')
		flags = '${' .. rec.name .. '_flags}'
		parent:write_part("ffi_pre",{
			'  local ',flags,' = OBJ_UDATA_FLAG_OWN\n'
		})
	end
	-- register variable for code gen (i.e. so ${var_name} is replaced with true variable name).
	parent:add_rec_var(rec)
	-- don't generate code for '<any>' type parameters
	if rec.c_type == '<any>' then
		parent:write_part("ffi_pre",
			{'  local ${', rec.name, '}\n'})
		parent:write_part("ffi_return", { "${", rec.name, "}, " })
		return
	end

	local lua = rec.c_type_rec
	if lua.lang_type == 'string' and rec.has_length then
		-- add length ${var_name_len} variable
		parent:add_rec_var(rec, rec.name .. '_len')
		-- the function's code will provide the string's length.
		parent:write_part("ffi_pre",{
			'  local ${', rec.name ,'_len} = 0\n'
		})
	end
	-- if the variable's type has a default value, then initialize the variable.
	local init = ''
	if lua.default then
		init = ' = ' .. tostring(lua.default)
	end
	-- add C variable to hold value to be pushed.
	local ffi_unwrap = ''
	if rec.wrap == '&' then
		local temp_name = "${function_name}_" .. rec.name .. "_tmp"
		parent:write_part("ffi_temps",
			{'  local ', temp_name, ' = ffi.new("',rec.c_type,'[1]")\n'})
		parent:write_part("ffi_pre",
			{'  local ${', rec.name, '} = ', temp_name,'\n'})
		ffi_unwrap = '[0]'
	else
		parent:write_part("ffi_pre",
			{'  local ${', rec.name, '}\n'})
	end
	-- if this is a temp. variable, then we are done.
	if rec.is_temp then
		return
	end
	-- push Lua value onto the stack.
	local error_code = parent._has_error_code
	if error_code == rec then
		local err_type = error_code.c_type_rec
		-- if error_code is the first var_out, then push 'true' to signal no error.
		-- On error push 'false' and the error message.
		if rec._rec_idx == 1 then
			if err_type.ffi_is_error_check then
				parent:write_part("ffi_post", {
				'  -- check for error.\n',
				'  local ${', rec.name,'}_err\n',
				'  if ',err_type.ffi_is_error_check(error_code),' then\n',
				'    ${', rec.name, '}_err = ', lua:_ffi_push(rec, flags),
				'    ${', rec.name ,'} = nil\n',
				'  else\n',
				'    ${', rec.name ,'} = true\n',
				'  end\n',
				})
			end
			parent:write_part("ffi_return", { "${", rec.name, "}, ${", rec.name, "}_err, " })
		else
			parent:write_part("ffi_post", {
				'  ${', rec.name ,'} = ', lua:_ffi_push(rec, flags), ffi_unwrap
			})
			parent:write_part("ffi_return", { "${", rec.name, "}, " })
		end
	elseif rec.no_nil_on_error ~= true and error_code then
		local err_type = error_code.c_type_rec
		-- return nil for this out variable, if there was an error.
		if err_type.ffi_is_error_check then
			parent:write_part("ffi_post", {
			'  if not ',err_type.ffi_is_error_check(error_code),' then\n',
			'    ${', rec.name, '} = ', lua:_ffi_push(rec, flags), ffi_unwrap,
			'  else\n',
			'    ${', rec.name, '} = nil\n',
			'  end\n',
			})
		end
		parent:write_part("ffi_return", { "${", rec.name, "}, " })
	elseif rec.is_error_on_null then
		-- if a function return NULL, then there was an error.
		parent:write_part("ffi_post", {
		'  local ${', rec.name,'}_err\n',
		'  if ',lua.ffi_is_error_check(rec),' then\n',
		'    ${', rec.name, '}_err = ', lua:_ffi_push_error(rec), ffi_unwrap,
		'  else\n',
		'    ${', rec.name, '} = ', lua:_ffi_push(rec, flags), ffi_unwrap,
		'  end\n',
		})
		parent:write_part("ffi_return", { "${", rec.name, "}, ${", rec.name, "}_err, " })
	else
		parent:write_part("ffi_post", {
			'  ${', rec.name ,'} = ', lua:_ffi_push(rec, flags), ffi_unwrap
		})
		parent:write_part("ffi_return", { "${", rec.name, "}, " })
	end
end,
cb_in = function(self, rec, parent)
end,
cb_out = function(self, rec, parent)
end,
}

print("Finished generating LuaJIT FFI bindings")

