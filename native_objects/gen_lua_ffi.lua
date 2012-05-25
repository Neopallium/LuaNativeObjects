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
typedef int (*ffi_export_func_t)(void);
typedef struct ffi_export_symbol {
	const char *name;
	union {
	void               *data;
	ffi_export_func_t  func;
	} sym;
} ffi_export_symbol;
#endif
]]

local objHelperFunc = [[
#if LUAJIT_FFI

/* nobj_ffi_support_enabled_hint should be set to 1 when FFI support is enabled in at-least one
 * instance of a LuaJIT state.  It should never be set back to 0. */
static int nobj_ffi_support_enabled_hint = 0;
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
		/* use results of previous check. */
		goto finished;
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

finished:
	/* turn-on hint that there is FFI code enabled. */
	if(rc) {
		nobj_ffi_support_enabled_hint = 1;
	}

	return rc;
}

typedef struct {
	const char **ffi_init_code;
	int offset;
} nobj_reader_state;

static const char *nobj_lua_Reader(lua_State *L, void *data, size_t *size) {
	nobj_reader_state *state = (nobj_reader_state *)data;
	const char *ptr;

	(void)L;
	ptr = state->ffi_init_code[state->offset];
	if(ptr != NULL) {
		*size = strlen(ptr);
		state->offset++;
	} else {
		*size = 0;
	}
	return ptr;
}

static int nobj_try_loading_ffi(lua_State *L, const char *ffi_mod_name,
		const char *ffi_init_code[], const ffi_export_symbol *ffi_exports, int priv_table)
{
	nobj_reader_state state = { ffi_init_code, 0 };
	int err;

	/* export symbols to priv_table. */
	while(ffi_exports->name != NULL) {
		lua_pushstring(L, ffi_exports->name);
		lua_pushlightuserdata(L, ffi_exports->sym.data);
		lua_settable(L, priv_table);
		ffi_exports++;
	}
	err = lua_load(L, nobj_lua_Reader, &state, ffi_mod_name);
	if(0 == err) {
		lua_pushvalue(L, -2); /* dup C module's table. */
		lua_pushvalue(L, priv_table); /* move priv_table to top of stack. */
		lua_remove(L, priv_table);
		lua_pushvalue(L, LUA_REGISTRYINDEX);
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
	if global then return ffi.C end
	return C
end
local function ffi_load(name, global)
	return assert(ffi_safe_load(name, global))
end

local function ffi_string(ptr)
	if ptr ~= nil then
		return ffi.string(ptr)
	end
	return nil
end

local function ffi_string_len(ptr, len)
	if ptr ~= nil then
		return ffi.string(ptr, len)
	end
	return nil
end

local error = error
local type = type
local tonumber = tonumber
local tostring = tostring
local sformat = require"string".format
local rawset = rawset
local setmetatable = setmetatable
local package = (require"package") or {}
local p_config = package.config
local p_cpath = package.cpath


local ffi_load_cmodule

-- try to detect luvit.
if p_config == nil and p_cpath == nil then
	ffi_load_cmodule = function(name, global)
		for path,module in pairs(package.loaded) do
			if module == name then
				local C, err = ffi_safe_load(path, global)
				-- return opened library
				if C then return C end
			end
		end
		error("Failed to find: " .. name)
	end
else
	ffi_load_cmodule = function(name, global)
		local dir_sep = p_config:sub(1,1)
		local path_sep = p_config:sub(3,3)
		local path_mark = p_config:sub(5,5)
		local path_match = "([^" .. path_sep .. "]*)" .. path_sep
		-- convert dotted name to directory path.
		name = name:gsub('%.', dir_sep)
		-- try each path in search path.
		for path in p_cpath:gmatch(path_match) do
			local fname = path:gsub(path_mark, name)
			local C, err = ffi_safe_load(fname, global)
			-- return opened library
			if C then return C end
		end
		error("Failed to find: " .. name)
	end
end

local _M, _priv, reg_table = ...
local REG_MODULES_AS_GLOBALS = false
local REG_OBJECTS_AS_GLOBALS = false
local C = ffi.C

local OBJ_UDATA_FLAG_OWN		= 1

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

local nobj_callback_states = {}
local nobj_weak_objects = setmetatable({}, {__mode = "v"})
local nobj_obj_flags = {}

local function obj_ptr_to_id(ptr)
	return tonumber(ffi.cast('uintptr_t', ptr))
end

local function obj_to_id(ptr)
	return tonumber(ffi.cast('uintptr_t', ffi.cast('void *', ptr)))
end

local function register_default_constructor(_pub, obj_name, constructor)
	local obj_pub = _pub[obj_name]
	if type(obj_pub) == 'table' then
		-- copy table since it might have a locked metatable
		local new_pub = {}
		for k,v in pairs(obj_pub) do
			new_pub[k] = v
		end
		setmetatable(new_pub, { __call = function(t,...)
			return constructor(...)
		end,
		__metatable = false,
		})
		obj_pub = new_pub
	else
		obj_pub = constructor
	end
	_pub[obj_name] = obj_pub
	_M[obj_name] = obj_pub
	if REG_OBJECTS_AS_GLOBALS then
		_G[obj_name] = obj_pub
	end
end
]===]

-- templates for typed *_check/*_delete/*_push functions
local ffi_obj_type_check_delete_push = {
['simple'] = [[
local obj_type_${object_name}_check
local obj_type_${object_name}_delete
local obj_type_${object_name}_push

do
	ffi_safe_cdef("${object_name}_simple_wrapper", [=[
		struct ${object_name}_t {
			const ${object_name} _wrapped_val;
		};
		typedef struct ${object_name}_t ${object_name}_t;
	]=])

	local obj_mt = _priv.${object_name}
	local obj_type = obj_mt['.type']
	local obj_ctype = ffi.typeof("${object_name}_t")
	_ctypes.${object_name} = obj_ctype
	_type_names.${object_name} = tostring(obj_ctype)

	function obj_type_${object_name}_check(obj)
		return obj._wrapped_val
	end

	function obj_type_${object_name}_delete(obj)
		local id = obj_to_id(obj)
		local valid = nobj_obj_flags[id]
		if not valid then return nil end
		local val = obj._wrapped_val
		nobj_obj_flags[id] = nil
		return val
	end

	function obj_type_${object_name}_push(val)
		local obj = obj_ctype(val)
		local id = obj_to_id(obj)
		nobj_obj_flags[id] = true
		return obj
	end

	function obj_mt:__tostring()
		return sformat("${object_name}: %d", tonumber(self._wrapped_val))
	end

	function obj_mt.__eq(val1, val2)
		if not ffi.istype(obj_ctype, val2) then return false end
		return (val1._wrapped_val == val2._wrapped_val)
	end

	-- type checking function for C API.
	_priv[obj_type] = function(obj)
		if ffi.istype(obj_ctype, obj) then return obj._wrapped_val end
		return nil
	end
	-- push function for C API.
	reg_table[obj_type] = function(ptr)
		return obj_type_${object_name}_push(ffi.cast("${object_name} *", ptr)[0])
	end

end

]],
['simple ptr'] = [[
local obj_type_${object_name}_check
local obj_type_${object_name}_delete
local obj_type_${object_name}_push

do
	local obj_mt = _priv.${object_name}
	local obj_type = obj_mt['.type']
	local obj_ctype = ffi.typeof("${object_name} *")
	_ctypes.${object_name} = obj_ctype
	_type_names.${object_name} = tostring(obj_ctype)

	function obj_type_${object_name}_check(ptr)
		return ptr
	end

	function obj_type_${object_name}_delete(ptr)
		local id = obj_ptr_to_id(ptr)
		local flags = nobj_obj_flags[id]
		if not flags then return ptr end
		ffi.gc(ptr, nil)
		nobj_obj_flags[id] = nil
		return ptr
	end

	if obj_mt.__gc then
		-- has __gc metamethod
		function obj_type_${object_name}_push(ptr)
			local id = obj_ptr_to_id(ptr)
			nobj_obj_flags[id] = true
			return ffi.gc(ptr, obj_mt.__gc)
		end
	else
		-- no __gc metamethod
		function obj_type_${object_name}_push(ptr)
			return ptr
		end
	end

	function obj_mt:__tostring()
		return sformat("${object_name}: %p", self)
	end

	-- type checking function for C API.
	_priv[obj_type] = function(ptr)
		if ffi.istype(obj_ctype, ptr) then return ptr end
		return nil
	end
	-- push function for C API.
	reg_table[obj_type] = function(ptr)
		return obj_type_${object_name}_push(ffi.cast(obj_ctype, ptr)[0])
	end

end

]],
['embed'] = [[
local obj_type_${object_name}_check
local obj_type_${object_name}_delete
local obj_type_${object_name}_push

do
	local obj_mt = _priv.${object_name}
	local obj_type = obj_mt['.type']
	local obj_ctype = ffi.typeof("${object_name}")
	_ctypes.${object_name} = obj_ctype
	_type_names.${object_name} = tostring(obj_ctype)
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

	function obj_mt:__tostring()
		return sformat("${object_name}: %p", self)
	end

	function obj_mt.__eq(val1, val2)
		if not ffi.istype(obj_type, val2) then return false end
		assert(ffi.istype(obj_type, val1), "expected ${object_name}")
		return (C.memcmp(val1, val2, ${object_name}_sizeof) == 0)
	end

	-- type checking function for C API.
	_priv[obj_type] = function(obj)
		if ffi.istype(obj_type, obj) then return obj end
		return nil
	end
	-- push function for C API.
	reg_table[obj_type] = function(ptr)
		local obj = obj_ctype()
		ffi.copy(obj, ptr, ${object_name}_sizeof);
		return obj
	end

end

]],
['object id'] = [[
local obj_type_${object_name}_check
local obj_type_${object_name}_delete
local obj_type_${object_name}_push

do
	ffi_safe_cdef("${object_name}_simple_wrapper", [=[
		struct ${object_name}_t {
			const ${object_name} _wrapped_val;
		};
		typedef struct ${object_name}_t ${object_name}_t;
	]=])

	local obj_mt = _priv.${object_name}
	local obj_type = obj_mt['.type']
	local obj_ctype = ffi.typeof("${object_name}_t")
	_ctypes.${object_name} = obj_ctype
	_type_names.${object_name} = tostring(obj_ctype)

	function obj_type_${object_name}_check(obj)
		-- if obj is nil or is the correct type, then just return it.
		if not obj or ffi.istype(obj_ctype, obj) then return obj._wrapped_val end
		-- check if it is a compatible type.
		local ctype = tostring(ffi.typeof(obj))
		local bcaster = _obj_subs.${object_name}[ctype]
		if bcaster then
			return bcaster(obj._wrapped_val)
		end
		return error("Expected '${object_name}'", 2)
	end

	function obj_type_${object_name}_delete(obj)
		local id = obj_to_id(obj)
		local flags = nobj_obj_flags[id]
		local val = obj._wrapped_val
		if not flags then return nil, 0 end
		nobj_obj_flags[id] = nil
		return val, flags
	end

	function obj_type_${object_name}_push(val, flags)
		local obj = obj_ctype(val)
		local id = obj_to_id(obj)
		nobj_obj_flags[id] = flags
		return obj
	end

	function obj_mt:__tostring()
		local val = self._wrapped_val
		return sformat("${object_name}: %d, flags=%d",
			tonumber(val), nobj_obj_flags[obj_to_id(val)] or 0)
	end

	function obj_mt.__eq(val1, val2)
		if not ffi.istype(obj_ctype, val2) then return false end
		return (val1._wrapped_val == val2._wrapped_val)
	end

	-- type checking function for C API.
	_priv[obj_type] = function(obj)
		if ffi.istype(obj_ctype, obj) then return obj._wrapped_val end
		return nil
	end
	-- push function for C API.
	reg_table[obj_type] = function(ptr, flags)
		return obj_type_${object_name}_push(ffi.cast('uintptr_t',ptr), flags)
	end

end

]],
['generic'] = [[
local obj_type_${object_name}_check
local obj_type_${object_name}_delete
local obj_type_${object_name}_push

do
	local obj_mt = _priv.${object_name}
	local obj_type = obj_mt['.type']
	local obj_ctype = ffi.typeof("${object_name} *")
	_ctypes.${object_name} = obj_ctype
	_type_names.${object_name} = tostring(obj_ctype)

	function obj_type_${object_name}_check(ptr)
		-- if ptr is nil or is the correct type, then just return it.
		if not ptr or ffi.istype(obj_ctype, ptr) then return ptr end
		-- check if it is a compatible type.
		local ctype = tostring(ffi.typeof(ptr))
		local bcaster = _obj_subs.${object_name}[ctype]
		if bcaster then
			return bcaster(ptr)
		end
		return error("Expected '${object_name} *'", 2)
	end

	function obj_type_${object_name}_delete(ptr)
		local id = obj_ptr_to_id(ptr)
		local flags = nobj_obj_flags[id]
		if not flags then return nil, 0 end
		ffi.gc(ptr, nil)
		nobj_obj_flags[id] = nil
		return ptr, flags
	end

	function obj_type_${object_name}_push(ptr, flags)
${dyn_caster}
		if flags ~= 0 then
			local id = obj_ptr_to_id(ptr)
			nobj_obj_flags[id] = flags
			ffi.gc(ptr, obj_mt.__gc)
		end
		return ptr
	end

	function obj_mt:__tostring()
		return sformat("${object_name}: %p, flags=%d", self, nobj_obj_flags[obj_ptr_to_id(self)] or 0)
	end

	-- type checking function for C API.
	_priv[obj_type] = function(ptr)
		if ffi.istype(obj_ctype, ptr) then return ptr end
		return nil
	end
	-- push function for C API.
	reg_table[obj_type] = function(ptr, flags)
		return obj_type_${object_name}_push(ffi.cast(obj_ctype,ptr), flags)
	end

end

]],
['generic_weak'] = [[
local obj_type_${object_name}_check
local obj_type_${object_name}_delete
local obj_type_${object_name}_push

do
	local obj_mt = _priv.${object_name}
	local obj_type = obj_mt['.type']
	local obj_ctype = ffi.typeof("${object_name} *")
	_ctypes.${object_name} = obj_ctype
	_type_names.${object_name} = tostring(obj_ctype)

	function obj_type_${object_name}_check(ptr)
		-- if ptr is nil or is the correct type, then just return it.
		if not ptr or ffi.istype(obj_ctype, ptr) then return ptr end
		-- check if it is a compatible type.
		local ctype = tostring(ffi.typeof(ptr))
		local bcaster = _obj_subs.${object_name}[ctype]
		if bcaster then
			return bcaster(ptr)
		end
		return error("Expected '${object_name} *'", 2)
	end

	function obj_type_${object_name}_delete(ptr)
		local id = obj_ptr_to_id(ptr)
		local flags = nobj_obj_flags[id]
		if not flags then return nil, 0 end
		ffi.gc(ptr, nil)
		nobj_obj_flags[id] = nil
		return ptr, flags
	end

	function obj_type_${object_name}_push(ptr, flags)
		local id = obj_ptr_to_id(ptr)
		-- check weak refs
		if nobj_obj_flags[id] then return nobj_weak_objects[id] end
${dyn_caster}
		if flags ~= 0 then
			nobj_obj_flags[id] = flags
			ffi.gc(ptr, obj_mt.__gc)
		end
		nobj_weak_objects[id] = ptr
		return ptr
	end

	function obj_mt:__tostring()
		return sformat("${object_name}: %p, flags=%d", self, nobj_obj_flags[obj_ptr_to_id(self)] or 0)
	end

	-- type checking function for C API.
	_priv[obj_type] = function(ptr)
		if ffi.istype(obj_ctype, ptr) then return ptr end
		return nil
	end
	-- push function for C API.
	reg_table[obj_type] = function(ptr, flags)
		return obj_type_${object_name}_push(ffi.cast(obj_ctype,ptr), flags)
	end

end

]],
}

local ffi_obj_metatype = {
['simple'] = "${object_name}_t",
['simple ptr'] = "${object_name}_t",
['embed'] = "${object_name}",
['object id'] = "${object_name}_t",
['generic'] = nil,
['generic_weak'] = "${object_name}",
}

local function get_var_name(var)
	local name = 'self'
	if not var.is_this then
		name = '${' .. var.name .. '}'
	end
	return name
end
local function unwrap_value(self, var)
	local name = get_var_name(var)
	return name .. ' = ' .. name .. '._wrapped_val\n'
end
local function no_wrapper(self, var) return '\n' end
local ffi_obj_type_check = {
['simple'] = unwrap_value,
['simple ptr'] = no_wrapper,
['embed'] = no_wrapper,
['object id'] = unwrap_value,
['generic'] = no_wrapper,
['generic_weak'] = no_wrapper,
}

-- module template
local ffi_module_template = [[
local _pub = {}
local _meth = {}
local _push = {}
local _obj_subs = {}
local _type_names = {}
local _ctypes = {}
for obj_name,mt in pairs(_priv) do
	if type(mt) == 'table' then
		_obj_subs[obj_name] = {}
		if mt.__index then
			_meth[obj_name] = mt.__index
		end
	end
end
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

local MAX_C_LITERAL = (16 * 1024)
local function dump_lua_code_to_c_str(code, name)
	-- make Lua code C-safe
	code = code:gsub('[\n"\\%z]', {
	['\n'] = "\\n\"\n\"",
	['\r'] = "\\r",
	['"'] = [[\"]],
	['\\'] = [[\\]],
	['\0'] = [[\0]],
	})
	local tcode = {'\nstatic const char *', name, '[] = { "', }
	-- find all cut positions.
	local last_pos = 1
	local next_boundry = last_pos + MAX_C_LITERAL
	local cuts = {} -- list of positions to cut the code at.
	for pos in code:gmatch("()\n") do -- find end position of all lines.
		-- check if current line will cross a cut boundry.
		if pos > next_boundry then
			-- cut code at end of last line.
			cuts[#cuts + 1] = last_pos
			next_boundry = pos + MAX_C_LITERAL
		end
		-- track end of last line.
		last_pos = pos
	end
	cuts[#cuts + 1] = last_pos
	-- split Lua code into multiple pieces if it is too long.
	last_pos = 1
	for i=1,#cuts do
		local pos = cuts[i]
		local piece = code:sub(last_pos, pos-1)
		last_pos = pos
		if(i > 1) then
			-- cut last piece.
			tcode[#tcode + 1] = ", /* ----- CUT ----- */"
		end
		tcode[#tcode + 1] = piece
	end
	tcode[#tcode + 1] = ', NULL };'

	return tcode
end

local function gen_if_defs_code(rec)
	if rec.ffi_if_defs then return end
	-- generate if code for if_defs.
	local if_defs = rec.if_defs
	local endif = 'end\n'
	if if_defs then
		if_defs = "if (" .. rec.obj_table .. rec.ffi_reg_name .. ') then\n'
	else
		if_defs = ''
		endif = ''
	end
	rec.ffi_if_defs = if_defs
	rec.ffi_endif = endif
end

local function reg_object_function(self, func, object)
	local ffi_table = '_meth'
	local name = func.name
	local reg_list
	-- check if this is object free/destructure method
	if func.is_destructor then
		if func._is_hidden then
			-- don't register '__gc' metamethods as a public object method.
			return '_priv.${object_name}.', '_priv', '__gc'
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
	local obj_table = ffi_table .. '.${object_name}.'
	if object._rec_type == 'c_module' then
		obj_table = '_M.'
	end
	return obj_table, ffi_table, name
end

local function add_source(rec, part, src, pos)
	return rec:insert_record(c_source(part)(src), 1)
end

print"============ Lua bindings ================="
-- do some pre-processing of objects.
process_records{
object = function(self, rec, parent)
	if rec.is_package then return end
	local ud_type = rec.userdata_type
	if not rec.no_weak_ref then
		ud_type = ud_type .. '_weak'
	end
	rec.ud_type = ud_type
	-- create _ffi_check_fast function
	rec._ffi_check_fast = ffi_obj_type_check[ud_type]
end,
}

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
	-- module_globals?
	rec:write_part("ffi_obj_type",
		{'REG_MODULES_AS_GLOBALS = ',(rec.module_globals and 'true' or 'false'),'\n'})
	-- use_globals?
	rec:write_part("ffi_obj_type",
		{'REG_OBJECTS_AS_GLOBALS = ',(rec.use_globals and 'true' or 'false'),'\n'})
	-- luajit_ffi_load_cmodule?
	if rec.luajit_ffi_load_cmodule then
		local global = 'false'
		if rec.luajit_ffi_load_cmodule == 'global' then
			global = 'true'
		end
		rec:write_part("ffi_typedef", {[[
local Cmod = ffi_load_cmodule("${module_c_name}", ]], global ,[[)
local C = Cmod

]]})
	end
	-- where we want the module function registered.
	rec.functions_regs = 'function_regs'
	rec.methods_regs = 'function_regs'
	-- symbols to export to FFI
	rec:write_part("ffi_export", {
		'#if LUAJIT_FFI\n',
		'static const ffi_export_symbol ${module_c_name}_ffi_export[] = {\n'})
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
	'  {NULL, { NULL } }\n',
	'};\n',
	'#endif\n\n'
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
			"ffi_pre_cdef", "ffi_typedef", "ffi_cdef", "ffi_obj_type", "ffi_import", "ffi_src",
			"ffi_metas_regs", "ffi_extends"
		}
		rec:write_part("ffi_code",
			dump_lua_code_to_c_str(ffi_code, '${module_c_name}_ffi_lua_code'))
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
	local ffi_parts = { "ffi_pre_cdef", "ffi_typedef", "ffi_cdef", "ffi_src" }
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
	if rec.has_dyn_caster then
		local flags = ''
		if rec.has_obj_flags then
			flags = ', flags'
		end
		rec:add_var('dyn_caster', [[
		local cast_obj = ]] .. rec.has_dyn_caster.dyn_caster_name .. [[(ptr]] .. flags .. [[)
		if cast_obj then return cast_obj end
]])
	else
		rec:add_var('dyn_caster', "")
	end
	-- register metatable for FFI cdata type.
	if not rec.is_package then
		-- create FFI check/delete/push functions
		rec:write_part("ffi_obj_type", {
			rec.ffi_custom_delete_push or ffi_obj_type_check_delete_push[rec.ud_type],
			'\n'
		})
		local c_metatype = ffi_obj_metatype[rec.ud_type]
		if c_metatype then
			rec:write_part("ffi_src",{
				'_push.${object_name} = obj_type_${object_name}_push\n',
				'ffi.metatype("',c_metatype,'", _priv.${object_name})\n',
		})
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
		'  {NULL, { NULL } }\n',
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
			"ffi_pre_cdef", "ffi_typedef", "ffi_cdef", "ffi_obj_type", "ffi_import", "ffi_src",
			"ffi_metas_regs", "ffi_extends"
		}
		rec:write_part("ffi_code",
			dump_lua_code_to_c_str(ffi_code, '${module_c_name}_${object_name}_ffi_lua_code'))
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
		local ffi_parts = { "ffi_pre_cdef", "ffi_typedef", "ffi_cdef", "ffi_import", "ffi_src",
			"ffi_metas_regs", "ffi_extends"
		}
		rec:vars_parts(ffi_parts)
		parent:copy_parts(rec, ffi_parts)
	end

end,
callback_state = function(self, rec, parent)
	rec:add_var('wrap_type', rec.wrap_type)
	rec:add_var('base_type', rec.base_type)
	-- generate allocate function for base type.
	rec:write_part("extra_code", [[

/* object allocation function for FFI bindings. */
${base_type} *nobj_ffi_${base_type}_new() {
	${base_type} *obj;
	obj_type_new(${base_type}, obj);
	return obj;
}
void nobj_ffi_${base_type}_free(${base_type} *obj) {
	obj_type_free(${base_type}, obj);
}

]])
	rec:write_part("ffi_cdef", "${base_type} *nobj_ffi_${base_type}_new();\n")
	rec:write_part("ffi_cdef", "void nobj_ffi_${base_type}_free(${base_type} *obj);\n")
end,
callback_state_end = function(self, rec, parent)
	-- apply variables to parts
	local parts = {"ffi_cdef", "ffi_src", "extra_code"}
	rec:vars_parts(parts)
	add_source(rec, "extra_code", rec:dump_parts("extra_code"))
	-- copy parts to parent
	parent:copy_parts(rec, parts)
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
				gen_if_defs_code(val)
				-- register base class's method with sub class
				local obj_table, ffi_table, name = reg_object_function(self, val, parent)
				-- write ffi code to remove registered base class method.
				parent:write_part("ffi_src",
				{obj_table, name, ' = nil\n'})
				-- write ffi code to copy method from base class.
				parent:write_part("ffi_extends",
				{val.ffi_if_defs, obj_table,name,' = ',
					ffi_table,'.',base.name,'.',name,'\n', val.ffi_endif})
			end
		end
	end
	-- base_caster: helper functions.
	local function base_caster_name(class_name, base_name)
		return 'base_cast_' .. class_name .. '_to_' .. base_name
	end
	local function create_base_caster(class, base, cast_type)
		local base_cast = base_caster_name(class.name, base.name)
		local caster_def = base.c_type .. ' nobj_ffi_' .. base_cast .. 
			'(' .. class.c_type .. ' obj)'
		if cast_type == 'direct' then
			rec:write_part('ffi_src', {
			'\n',
			'-- add sub-class to base classes list of subs\n',
			'_obj_subs.', base.name, '[_type_names.${object_name}] = function(obj)\n',
			'  return ffi.cast(_ctypes.', base.name,',obj)\n',
			'end\n\n',
			})
			return base_cast
		end
		-- add base_cast decl.
		parent:write_part('ffi_cdef', {' ', caster_def, ';\n'})
		-- start base_cast function.
		if class.is_ptr then
			rec:write_part('src', {
			caster_def, ' {\n',
			'  void *ptr = (void *)obj;\n',
			'  ', base_cast, '(&ptr);\n',
			'  return (',base.c_type,')ptr;\n',
			'}\n\n',
			})
		else
			rec:write_part('src', {
			caster_def, ' {\n',
			'  void *ptr = (void *)(uintptr_t)obj;\n',
			'  ', base_cast, '(&ptr);\n',
			'  return (',base.c_type,')(uintptr_t)ptr;\n',
			'}\n\n',
			})
		end
		-- add sub-classes to base class list of subs.
		parent:write_part("ffi_extends",
			{'-- add sub-class to base classes list of subs\n',
			 '_obj_subs.', base.name, '[_type_names.${object_name}] = C.nobj_ffi_',base_cast,'\n',
			})
	end
	-- add casters for all base-class's ancestors
	for name,extend in pairs(base.extends) do
		create_base_caster(parent, extend.base, extend.cast_type)
	end
	-- create caster to base type.
	create_base_caster(parent, base, rec.cast_type)
end,
extends_end = function(self, rec, parent)
	-- map in/out variables in c source.
	local parts = {"src", "ffi_src"}
	rec:vars_parts(parts)

	-- append ffi wrapper function for base caster functions.
	add_source(parent, "extra_code", rec:dump_parts("src"))

	-- copy parts to parent
	parent:copy_parts(rec, "ffi_src")
end,
callback_func = function(self, rec, parent)
	rec.wrapped_type = parent.c_type
	rec.wrapped_type_rec = parent.c_type_rec
	-- add callback typedef
	rec:write_part('ffi_cdef', {rec.c_func_typedef, '\n'})
	-- start callback function.
	rec:write_part("ffi_cb_head",
	{'-- callback: ', rec.name, '\n',
	 'local ', rec.c_func_name, ' = ffi.cast("',rec.c_type,'",function (', rec.param_vars, ')\n',
	})
	-- add lua reference to wrapper object.
	parent:write_part('wrapper_callbacks',
	  {'  int ', rec.ref_field, ';\n'})
end,
callback_func_end = function(self, rec, parent)
	local wrapped = rec.wrapped_var
	local wrapped_type = wrapped.c_type_rec
	local wrap_type = parent.wrap_type .. ' *'
	rec:write_part("ffi_cb_head",
	{'  local id = obj_ptr_to_id(', wrapped_type:_ffi_push(wrapped) ,')\n',
	 '  local wrap = nobj_callback_states[id]\n',
	})
	-- generate code for return value from lua function.
	local ret_out = rec.ret_out
	local func_rc = ''
	if ret_out then
		func_rc = 'ret'
		rec:write_part("ffi_post", {'  return ret\n'})
	end
	-- call lua callback function.
	local cb_params = rec:dump_parts("ffi_cb_params")
	cb_params = cb_params:gsub(", $","")
	rec:write_part("ffi_pre_src", {
	'  local status, ret = pcall(wrap.' .. rec.ref_field,', ', cb_params,')\n',
	'  if not status then\n',
	})
	rec:write_part("ffi_post_src", {
	'    print("CALLBACK Error:", ret)\n',
	'    return ', func_rc ,'\n',
	'  end\n',
	})
	rec:write_part("ffi_post", {'end)\n\n'})
	-- map in/out variables in c source.
	local parts = {"ffi_cb_head", "ffi_pre_src", "ffi_src", "ffi_post_src", "ffi_post"}
	rec:vars_parts(parts)
	rec:vars_parts('ffi_cdef')

	parent:write_part('ffi_src', rec:dump_parts(parts))
	parent:write_part('ffi_cdef', rec:dump_parts('ffi_cdef'))
end,
dyn_caster = function(self, rec, parent)
	local vtab = rec.ffi_value_table or ''
	if vtab ~= '' then
		vtab = '_pub.' .. vtab .. '.'
	end
	rec.dyn_caster_name = 'dyn_caster_' .. parent.name
	-- generate lookup table for switch based caster.
	if rec.caster_type == 'switch' then
		local lookup_table = { "local dyn_caster_${object_name}_lookup = {\n" }
		local selector = ''
		if rec.value_field then
			selector = 'obj.' .. rec.value_field
		elseif rec.value_function then
			selector = "C." .. rec.value_function .. '(obj)'
		else
			error("Missing switch value for dynamic caster.")
		end
		rec:write_part('src', {
			'  local sub_type = dyn_caster_${object_name}_lookup[', selector, ']\n',
			'  local type_push = _push[sub_type or 0]\n',
			'  if type_push then return type_push(ffi.cast(_ctypes[sub_type],obj), flags) end\n',
			'  return nil\n',
		})
		-- add cases for each sub-object type.
		for val,sub in pairs(rec.value_map) do
			lookup_table[#lookup_table + 1] = '[' .. vtab .. val .. '] = "' .. sub.name .. '",\n'
		end
		lookup_table[#lookup_table + 1] = '}\n\n'
		parent:write_part("ffi_obj_type", lookup_table)
	end
end,
dyn_caster_end = function(self, rec, parent)
	-- append custom dyn caster code
	parent:write_part("ffi_obj_type",
		{"local function dyn_caster_${object_name}(obj, flags)\n", rec:dump_parts{ "src" }, "end\n\n" })
end,
c_function = function(self, rec, parent)
	rec:add_var('object_name', parent.name)
	rec:add_var('function_name', rec.name)
	if rec.is_destructor then
		rec.__gc = true -- mark as '__gc' method
		-- check if this is the first destructor.
		if not parent.has_default_destructor then
			parent.has_default_destructor = rc
			rec.is__default_destructor = true
		end
	end

	-- register method/function with object.
	local obj_table, ffi_table, name = reg_object_function(self, rec, parent)
	rec.obj_table = obj_table
	rec.ffi_table = ffi_table
	rec.ffi_reg_name = name
	-- generate if code for if_defs.
	gen_if_defs_code(rec)

	-- generate FFI function
	rec:write_part("ffi_pre",
	{'-- method: ', name, '\n', rec.ffi_if_defs,
		'function ',obj_table, name, '(',rec.ffi_params,')\n'})
end,
c_function_end = function(self, rec, parent)
	-- don't generate FFI bindings
	if self._cur_module.ffi_manual_bindings then return end

	-- is this a wrapper function
	if rec.wrapper_obj then
		local wrap_obj = rec.wrapper_obj
		local wrap_type = wrap_obj.wrap_type
		local callbacks = wrap_obj.callbacks
		if rec.is_destructor then
			rec:write_part("ffi_pre",
				{'  local id = obj_ptr_to_id(${this})\n',
				 '  local wrap = nobj_callback_states[id]\n'})
			for name,cb in pairs(callbacks) do
				rec:write_part("ffi_src",
					{'  wrap.', name,' = nil\n'})
			end
			rec:write_part("ffi_post",
				{'  nobj_callback_states[id] = nil\n',
				 '  C.nobj_ffi_',wrap_obj.base_type,'_free(${this})\n',
				})
		elseif rec.is_constructor then
			rec:write_part("ffi_pre",
				{'  ${this} = C.nobj_ffi_',wrap_obj.base_type,'_new()\n',
				 '  local id = obj_ptr_to_id(${this})\n',
				 '  local wrap = {}\n',
				 '  nobj_callback_states[id] = wrap\n',
				})
		end
	end

	-- check if function has FFI support
	local ffi_src = rec:dump_parts("ffi_src")
	if rec.no_ffi or #ffi_src == 0 then return end

	-- generate if code for if_defs.
	local endif = '\n'
	if rec.if_defs then
		endif = 'end\n\n'
	end

	-- end Lua code for FFI function
	local ffi_parts = {"ffi_temps", "ffi_pre", "ffi_src", "ffi_post"}
	local ffi_return = rec:dump_parts("ffi_return")
	-- trim last ', ' from list of return values.
	ffi_return = ffi_return:gsub(", $","")
	rec:write_part("ffi_post",
		{'  return ', ffi_return,'\n',
		 'end\n', rec.ffi_endif})

	-- check if this is the default constructor.
	if rec.is_default_constructor then
		rec:write_part("ffi_post",
			{'register_default_constructor(_pub,"${object_name}",',
			rec.obj_table, rec.ffi_reg_name ,')\n'})
	end
	if rec.is__default_destructor and not rec._is_hidden and
			not self._cur_module.disable__gc and not parent.disable__gc then
		rec:write_part('ffi_post',
			{'_priv.${object_name}.__gc = ', rec.obj_table, rec.name, '\n'})
	end

	rec:vars_parts(ffi_parts)
	-- append FFI-based function to parent's FFI source
	local ffi_cdef = { "ffi_cdef" }
	rec:vars_parts(ffi_cdef)
	parent:write_part("ffi_cdef", rec:dump_parts(ffi_cdef))
	local temps = rec:dump_parts("ffi_temps")
	if #temps > 0 then
		parent:write_part("ffi_src", {"do\n", rec:dump_parts(ffi_parts), "end\n\n"})
	else
		parent:write_part("ffi_src", {rec:dump_parts(ffi_parts), "\n"})
	end
end,
c_source = function(self, rec, parent)
end,
ffi_export = function(self, rec, parent)
	parent:write_part("ffi_export",
		{'{ "', rec.name, '", { ', rec.name, ' } },\n'})
end,
ffi_source = function(self, rec, parent)
	parent:write_part(rec.part, rec.src)
	parent:write_part(rec.part, "\n")
end,
var_in = function(self, rec, parent)
	-- no need to add code for 'lua_State *' parameters.
	if rec.c_type == 'lua_State *' and rec.name == 'L' then return end
	-- register variable for code gen (i.e. so ${var_name} is replaced with true variable name).
	parent:add_rec_var(rec, rec.name, rec.is_this and 'self')
	-- don't generate code for '<any>' type parameters
	if rec.c_type == '<any>' then return end

	local var_type = rec.c_type_rec
	if rec.is_this and parent.__gc then
		if var_type.has_obj_flags then
			-- add flags ${var_name_flags} variable
			parent:add_rec_var(rec, rec.name .. '_flags')
			-- for garbage collect method, check the ownership flag before freeing 'this' object.
			parent:write_part("ffi_pre",
				{
				'  ', var_type:_ffi_delete(rec, true),
				'  if not ${',rec.name,'} then return end\n',
				})
		else
			-- for garbage collect method, check the ownership flag before freeing 'this' object.
			parent:write_part("ffi_pre",
				{
				'  ', var_type:_ffi_delete(rec, false),
				'  if not ${',rec.name,'} then return end\n',
				})
		end
	elseif var_type._rec_type ~= 'callback_func' then
		if var_type.lang_type == 'string' then
			-- add length ${var_name_len} variable
			parent:add_rec_var(rec, rec.name .. '_len')
		end
		-- check lua value matches type.
		local ffi_get
		if rec.is_optional then
			ffi_get = var_type:_ffi_opt(rec, rec.default)
		else
			ffi_get = var_type:_ffi_check(rec)
		end
		parent:write_part("ffi_pre",
			{'  ', ffi_get })
	end
	-- is a lua reference.
	if var_type.is_ref then
		parent:write_part("ffi_src",
			{'  wrap.', var_type.ref_field, ' = ${',rec.name,'}\n',
			 '  ${',rec.name,'} = ', rec.cb_func.c_func_name, '\n',
			 })
	end
end,
var_out = function(self, rec, parent)
	if rec.is_length_ref then
		return
	end
	local flags = false
	local var_type = rec.c_type_rec
	if var_type.has_obj_flags then
		if (rec.is_this or rec.own) then
			-- add flags ${var_name_flags} variable
			parent:add_rec_var(rec, rec.name .. '_flags')
			flags = '${' .. rec.name .. '_flags}'
			parent:write_part("ffi_pre",{
				'  local ',flags,' = OBJ_UDATA_FLAG_OWN\n'
			})
		else
			flags = "0"
		end
	end
	-- register variable for code gen (i.e. so ${var_name} is replaced with true variable name).
	parent:add_rec_var(rec, rec.name, rec.is_this and 'self')
	-- don't generate code for '<any>' type parameters
	if rec.c_type == '<any>' then
		if not rec.is_this then
			parent:write_part("ffi_pre",
				{'  local ${', rec.name, '}\n'})
		end
		parent:write_part("ffi_return", { "${", rec.name, "}, " })
		return
	end

	local var_type = rec.c_type_rec
	if var_type.lang_type == 'string' and rec.has_length then
		-- add length ${var_name_len} variable
		parent:add_rec_var(rec, rec.name .. '_len')
		-- the function's code will provide the string's length.
		parent:write_part("ffi_pre",{
			'  local ${', rec.name ,'_len} = 0\n'
		})
	end
	-- if the variable's type has a default value, then initialize the variable.
	local init = ''
	local default = var_type.default
	if default and default ~= 'NULL' then
		init = ' = ' .. tostring(default)
	elseif var_type.userdata_type == 'embed' then
		init = ' = ffi.new("' .. var_type.name .. '")'
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
			{'  local ${', rec.name, '}',init,'\n'})
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
				'  if ',err_type.ffi_is_error_check(error_code),' then\n',
				'    return nil, ', var_type:_ffi_push(rec, flags), '\n',
				'  end\n',
				})
				parent:write_part("ffi_return", { "true, " })
			end
		end
	elseif rec.no_nil_on_error ~= true and error_code then
		local err_type = error_code.c_type_rec
		-- return nil for this out variable, if there was an error.
		if err_type.ffi_is_error_check then
			parent:write_part("ffi_post", {
			'  if ',err_type.ffi_is_error_check(error_code),' then\n',
			'    return nil,', err_type:_ffi_push(error_code), '\n',
			'  end\n',
			})
		end
		parent:write_part("ffi_return", { var_type:_ffi_push(rec, flags, ffi_unwrap), ", " })
	elseif rec.is_error_on_null then
		-- if a function return NULL, then there was an error.
		parent:write_part("ffi_post", {
		'  if ',var_type.ffi_is_error_check(rec),' then\n',
		'    return nil, ', var_type:_ffi_push_error(rec), '\n',
		'  end\n',
		})
		parent:write_part("ffi_return", { var_type:_ffi_push(rec, flags, ffi_unwrap), ", " })
	else
		parent:write_part("ffi_return", { var_type:_ffi_push(rec, flags, ffi_unwrap), ", " })
	end
end,
cb_in = function(self, rec, parent)
	parent:add_rec_var(rec)
	local var_type = rec.c_type_rec
	if not rec.is_wrapped_obj then
		parent:write_part("ffi_cb_params", { var_type:_ffi_push(rec), ', ' })
	else
		-- this is the wrapped object parameter.
		parent.wrapped_var = rec
	end
end,
cb_out = function(self, rec, parent)
	parent:add_rec_var(rec, 'ret', 'ret')
	local var_type = rec.c_type_rec
	parent:write_part("ffi_post",
		{'  ', var_type:_ffi_opt(rec) })
end,
}

print("Finished generating LuaJIT FFI bindings")

