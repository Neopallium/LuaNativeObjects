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
-- try generating LuaJIT FFI bindings to include into the C module.
--
require("native_objects.gen_lua_ffi")

--
-- templates
--
local generated_output_header = [[
/***********************************************************************************************
************************************************************************************************
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!!!!!!! Warning this file was generated from a set of *.nobj.lua definition files !!!!!!!!!!!!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
************************************************************************************************
***********************************************************************************************/

]]

local obj_udata_types = [[

#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <errno.h>

#ifdef _MSC_VER
#define __WINDOWS__
#else
#if defined(_WIN32)
#define __WINDOWS__
#endif
#endif

#ifdef __WINDOWS__

/* for MinGW32 compiler need to include <stdint.h> */
#ifdef __GNUC__
#include <stdint.h>
#include <stdbool.h>
#else

/* define some standard types missing on Windows. */
#ifndef __INT32_MAX__
typedef __int32 int32_t;
typedef unsigned __int32 uint32_t;
#endif
#ifndef __INT64_MAX__
typedef __int64 int64_t;
typedef unsigned __int64 uint64_t;
#endif
typedef int bool;
#ifndef true
#define true 1
#endif
#ifndef false
#define false 0
#endif

#endif

/* wrap strerror_s(). */
#ifdef __GNUC__
#ifndef strerror_r
#define strerror_r(errno, buf, buflen) do { \
	strncpy((buf), strerror(errno), (buflen)-1); \
	(buf)[(buflen)-1] = '\0'; \
} while(0)
#endif
#else
#ifndef strerror_r
#define strerror_r(errno, buf, buflen) strerror_s((buf), (buflen), (errno))
#endif
#endif

#define FUNC_UNUSED

#define LUA_NOBJ_API __declspec(dllexport)

#else

#define LUA_NOBJ_API LUALIB_API

#include <stdint.h>
#include <stdbool.h>

#define FUNC_UNUSED __attribute__((unused))

#endif

#if defined(__GNUC__) && (__GNUC__ >= 4)
#define assert_obj_type(type, obj) \
	assert(__builtin_types_compatible_p(typeof(obj), type *))
#else
#define assert_obj_type(type, obj)
#endif

void *${nobj_realloc}(void *ptr, size_t osize, size_t nsize);

void *nobj_realloc(void *ptr, size_t osize, size_t nsize) {
	(void)osize;
	if(0 == nsize) {
		free(ptr);
		return NULL;
	}
	return realloc(ptr, nsize);
}

#define obj_type_free(type, obj) do { \
	assert_obj_type(type, obj); \
	${nobj_realloc}((obj), sizeof(type), 0); \
} while(0)

#define obj_type_new(type, obj) do { \
	assert_obj_type(type, obj); \
	(obj) = ${nobj_realloc}(NULL, 0, sizeof(type)); \
} while(0)

typedef struct obj_type obj_type;

typedef void (*base_caster_t)(void **obj);

typedef void (*dyn_caster_t)(void **obj, obj_type **type);

#define OBJ_TYPE_FLAG_WEAK_REF (1<<0)
#define OBJ_TYPE_SIMPLE (1<<1)
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

typedef enum obj_const_type {
	CONST_UNKOWN    = 0,
	CONST_BOOLEAN   = 1,
	CONST_NUMBER    = 2,
	CONST_STRING    = 3
} obj_const_type;

typedef struct obj_const {
	const char      *name;    /**< constant's name. */
	const char      *str;
	double          num;
	obj_const_type  type;
} obj_const;

typedef enum obj_field_type {
	TYPE_UNKOWN    = 0,
	TYPE_UINT8     = 1,
	TYPE_UINT16    = 2,
	TYPE_UINT32    = 3,
	TYPE_UINT64    = 4,
	TYPE_INT8      = 5,
	TYPE_INT16     = 6,
	TYPE_INT32     = 7,
	TYPE_INT64     = 8,
	TYPE_DOUBLE    = 9,
	TYPE_FLOAT     = 10,
	TYPE_STRING    = 11
} obj_field_type;

typedef struct obj_field {
	const char      *name;  /**< field's name. */
	uint32_t        offset; /**< offset to field's data. */
	obj_field_type  type;   /**< field's data type. */
	uint32_t        flags;  /**< is_writable:1bit */
} obj_field;

typedef enum {
	REG_OBJECT,
	REG_PACKAGE,
	REG_META,
} module_reg_type;

typedef struct reg_sub_module {
	obj_type        *type;
	module_reg_type req_type;
	const luaL_reg  *pub_funcs;
	const luaL_reg  *methods;
	const luaL_reg  *metas;
	const obj_base  *bases;
	const obj_field *fields;
	const obj_const *constants;
	int             bidirectional_consts;
} reg_sub_module;

#define OBJ_UDATA_FLAG_OWN (1<<0)
#define OBJ_UDATA_FLAG_LOOKUP (1<<1)
#define OBJ_UDATA_LAST_FLAG (OBJ_UDATA_FLAG_LOOKUP)
typedef struct obj_udata {
	void     *obj;
	uint32_t flags;  /**< lua_own:1bit */
} obj_udata;

/* use static pointer as key to weak userdata table. */
static char obj_udata_weak_ref_key[] = "obj_udata_weak_ref_key";

/* use static pointer as key to module's private table. */
static char obj_udata_private_key[] = "obj_udata_private_key";

]]

local objHelperFunc = [[
#ifndef REG_PACKAGE_IS_CONSTRUCTOR
#define REG_PACKAGE_IS_CONSTRUCTOR 1
#endif

#ifndef REG_MODULES_AS_GLOBALS
#define REG_MODULES_AS_GLOBALS 0
#endif

#ifndef REG_OBJECTS_AS_GLOBALS
#define REG_OBJECTS_AS_GLOBALS 0
#endif

#ifndef OBJ_DATA_HIDDEN_METATABLE
#define OBJ_DATA_HIDDEN_METATABLE 1
#endif

static FUNC_UNUSED obj_udata *obj_udata_toobj(lua_State *L, int _index) {
	obj_udata *ud;
	size_t len;

	/* make sure it's a userdata value. */
	ud = (obj_udata *)lua_touserdata(L, _index);
	if(ud == NULL) {
		luaL_typerror(L, _index, "userdata"); /* is not a userdata value. */
	}
	/* verify userdata size. */
	len = lua_objlen(L, _index);
	if(len != sizeof(obj_udata)) {
		/* This shouldn't be possible */
		luaL_error(L, "invalid userdata size: size=%d, expected=%d", len, sizeof(obj_udata));
	}
	return ud;
}

static FUNC_UNUSED int obj_udata_is_compatible(lua_State *L, obj_udata *ud, void **obj, base_caster_t *caster, obj_type *type) {
	obj_base *base;
	obj_type *ud_type;
	lua_pushlightuserdata(L, type);
	lua_rawget(L, LUA_REGISTRYINDEX); /* type's metatable. */
	if(lua_rawequal(L, -1, -2)) {
		*obj = ud->obj;
		/* same type no casting needed. */
		return 1;
	} else {
		/* Different types see if we can cast to the required type. */
		lua_rawgeti(L, -2, type->id);
		base = lua_touserdata(L, -1);
		lua_pop(L, 1); /* pop obj_base or nil */
		if(base != NULL) {
			*caster = base->bcaster;
			/* get the obj_type for this userdata. */
			lua_pushliteral(L, ".type");
			lua_rawget(L, -3); /* type's metatable. */
			ud_type = lua_touserdata(L, -1);
			lua_pop(L, 1); /* pop obj_type or nil */
			if(base == NULL) {
				luaL_error(L, "bad userdata, missing type info.");
				return 0;
			}
			/* check if userdata is a simple object. */
			if(ud_type->flags & OBJ_TYPE_SIMPLE) {
				*obj = ud;
			} else {
				*obj = ud->obj;
			}
			return 1;
		}
	}
	return 0;
}

static FUNC_UNUSED obj_udata *obj_udata_luacheck_internal(lua_State *L, int _index, void **obj, obj_type *type, int not_delete) {
	obj_udata *ud;
	base_caster_t caster = NULL;
	/* make sure it's a userdata value. */
	ud = (obj_udata *)lua_touserdata(L, _index);
	if(ud != NULL) {
		/* check object type by comparing metatables. */
		if(lua_getmetatable(L, _index)) {
			if(obj_udata_is_compatible(L, ud, obj, &(caster), type)) {
				lua_pop(L, 2); /* pop both metatables. */
				/* apply caster function if needed. */
				if(caster != NULL && *obj != NULL) {
					caster(obj);
				}
				/* check object pointer. */
				if(*obj == NULL) {
					if(not_delete) {
						luaL_error(L, "null %s", type->name); /* object was garbage collected? */
					}
					return NULL;
				}
				return ud;
			}
		}
	} else if(!lua_isnil(L, _index)) {
		/* handle cdata. */
		/* get private table. */
		lua_pushlightuserdata(L, obj_udata_private_key);
		lua_rawget(L, LUA_REGISTRYINDEX); /* private table. */
		/* get cdata type check function from private table. */
		lua_pushlightuserdata(L, type);
		lua_rawget(L, -2);

		/* check for function. */
		if(!lua_isnil(L, -1)) {
			/* pass cdata value to type checking function. */
			lua_pushvalue(L, _index);
			lua_call(L, 1, 1);
			if(!lua_isnil(L, -1)) {
				/* valid type get pointer from cdata. */
				lua_pop(L, 2);
				*obj = *(void **)lua_topointer(L, _index);
				return ud;
			}
			lua_pop(L, 2);
		} else {
			lua_pop(L, 1);
		}
	}
	if(not_delete) {
		luaL_typerror(L, _index, type->name); /* is not a userdata value. */
	}
	return NULL;
}

static FUNC_UNUSED void *obj_udata_luacheck(lua_State *L, int _index, obj_type *type) {
	void *obj = NULL;
	obj_udata_luacheck_internal(L, _index, &(obj), type, 1);
	return obj;
}

static FUNC_UNUSED void *obj_udata_luaoptional(lua_State *L, int _index, obj_type *type) {
	void *obj = NULL;
	if(lua_isnil(L, _index)) {
		return obj;
	}
	obj_udata_luacheck_internal(L, _index, &(obj), type, 1);
	return obj;
}

static FUNC_UNUSED void *obj_udata_luadelete(lua_State *L, int _index, obj_type *type, int *flags) {
	void *obj;
	obj_udata *ud = obj_udata_luacheck_internal(L, _index, &(obj), type, 0);
	if(ud == NULL) return NULL;
	*flags = ud->flags;
	/* null userdata. */
	ud->obj = NULL;
	ud->flags = 0;
	/* clear the metatable in invalidate userdata. */
	lua_pushnil(L);
	lua_setmetatable(L, _index);
	return obj;
}

static FUNC_UNUSED void obj_udata_luapush(lua_State *L, void *obj, obj_type *type, int flags) {
	obj_udata *ud;
	/* convert NULL's into Lua nil's. */
	if(obj == NULL) {
		lua_pushnil(L);
		return;
	}
#if LUAJIT_FFI
	lua_pushlightuserdata(L, type);
	lua_rawget(L, LUA_REGISTRYINDEX); /* type's metatable. */
	if(nobj_ffi_support_enabled_hint && lua_isfunction(L, -1)) {
		/* call special FFI "void *" to FFI object convertion function. */
		lua_pushlightuserdata(L, obj);
		lua_pushinteger(L, flags);
		lua_call(L, 2, 1);
		return;
	}
#endif
	/* check for type caster. */
	if(type->dcaster) {
		(type->dcaster)(&obj, &type);
	}
	/* create new userdata. */
	ud = (obj_udata *)lua_newuserdata(L, sizeof(obj_udata));
	ud->obj = obj;
	ud->flags = flags;
	/* get obj_type metatable. */
#if LUAJIT_FFI
	lua_insert(L, -2); /* move userdata below metatable. */
#else
	lua_pushlightuserdata(L, type);
	lua_rawget(L, LUA_REGISTRYINDEX); /* type's metatable. */
#endif
	lua_setmetatable(L, -2);
}

static FUNC_UNUSED void *obj_udata_luadelete_weak(lua_State *L, int _index, obj_type *type, int *flags) {
	void *obj;
	obj_udata *ud = obj_udata_luacheck_internal(L, _index, &(obj), type, 0);
	if(ud == NULL) return NULL;
	*flags = ud->flags;
	/* null userdata. */
	ud->obj = NULL;
	ud->flags = 0;
	/* clear the metatable in invalidate userdata. */
	lua_pushnil(L);
	lua_setmetatable(L, _index);
	/* get objects weak table. */
	lua_pushlightuserdata(L, obj_udata_weak_ref_key);
	lua_rawget(L, LUA_REGISTRYINDEX); /* weak ref table. */
	/* remove object from weak table. */
	lua_pushlightuserdata(L, obj);
	lua_pushnil(L);
	lua_rawset(L, -3);
	return obj;
}

static FUNC_UNUSED void obj_udata_luapush_weak(lua_State *L, void *obj, obj_type *type, int flags) {
	obj_udata *ud;

	/* convert NULL's into Lua nil's. */
	if(obj == NULL) {
		lua_pushnil(L);
		return;
	}
	/* check for type caster. */
	if(type->dcaster) {
		(type->dcaster)(&obj, &type);
	}
	/* get objects weak table. */
	lua_pushlightuserdata(L, obj_udata_weak_ref_key);
	lua_rawget(L, LUA_REGISTRYINDEX); /* weak ref table. */
	/* lookup userdata instance from pointer. */
	lua_pushlightuserdata(L, obj);
	lua_rawget(L, -2);
	if(!lua_isnil(L, -1)) {
		lua_remove(L, -2);     /* remove objects table. */
		return;
	}
	lua_pop(L, 1);  /* pop nil. */

#if LUAJIT_FFI
	lua_pushlightuserdata(L, type);
	lua_rawget(L, LUA_REGISTRYINDEX); /* type's metatable. */
	if(nobj_ffi_support_enabled_hint && lua_isfunction(L, -1)) {
		lua_remove(L, -2);
		/* call special FFI "void *" to FFI object convertion function. */
		lua_pushlightuserdata(L, obj);
		lua_pushinteger(L, flags);
		lua_call(L, 2, 1);
		return;
	}
#endif
	/* create new userdata. */
	ud = (obj_udata *)lua_newuserdata(L, sizeof(obj_udata));

	/* init. obj_udata. */
	ud->obj = obj;
	ud->flags = flags;
	/* get obj_type metatable. */
#if LUAJIT_FFI
	lua_insert(L, -2); /* move userdata below metatable. */
#else
	lua_pushlightuserdata(L, type);
	lua_rawget(L, LUA_REGISTRYINDEX); /* type's metatable. */
#endif
	lua_setmetatable(L, -2);

	/* add weak reference to object. */
	lua_pushlightuserdata(L, obj); /* push object pointer as the 'key' */
	lua_pushvalue(L, -2);          /* push object's udata */
	lua_rawset(L, -4);             /* add weak reference to object. */
	lua_remove(L, -2);     /* remove objects table. */
}

/* default object equal method. */
static FUNC_UNUSED int obj_udata_default_equal(lua_State *L) {
	obj_udata *ud1 = obj_udata_toobj(L, 1);
	obj_udata *ud2 = obj_udata_toobj(L, 2);

	lua_pushboolean(L, (ud1->obj == ud2->obj));
	return 1;
}

/* default object tostring method. */
static FUNC_UNUSED int obj_udata_default_tostring(lua_State *L) {
	obj_udata *ud = obj_udata_toobj(L, 1);

	/* get object's metatable. */
	lua_getmetatable(L, 1);
	lua_remove(L, 1); /* remove userdata. */
	/* get the object's name from the metatable */
	lua_getfield(L, 1, ".name");
	lua_remove(L, 1); /* remove metatable */
	/* push object's pointer */
	lua_pushfstring(L, ": %p, flags=%d", ud->obj, ud->flags);
	lua_concat(L, 2);

	return 1;
}

/*
 * Simple userdata objects.
 */
static FUNC_UNUSED void *obj_simple_udata_toobj(lua_State *L, int _index) {
	void *ud;

	/* make sure it's a userdata value. */
	ud = lua_touserdata(L, _index);
	if(ud == NULL) {
		luaL_typerror(L, _index, "userdata"); /* is not a userdata value. */
	}
	return ud;
}

static FUNC_UNUSED void * obj_simple_udata_luacheck(lua_State *L, int _index, obj_type *type) {
	void *ud;
	/* make sure it's a userdata value. */
	ud = lua_touserdata(L, _index);
	if(ud != NULL) {
		/* check object type by comparing metatables. */
		if(lua_getmetatable(L, _index)) {
			lua_pushlightuserdata(L, type);
			lua_rawget(L, LUA_REGISTRYINDEX); /* type's metatable. */
			if(lua_rawequal(L, -1, -2)) {
				lua_pop(L, 2); /* pop both metatables. */
				return ud;
			}
		}
	} else if(!lua_isnil(L, _index)) {
		/* handle cdata. */
		/* get private table. */
		lua_pushlightuserdata(L, obj_udata_private_key);
		lua_rawget(L, LUA_REGISTRYINDEX); /* private table. */
		/* get cdata type check function from private table. */
		lua_pushlightuserdata(L, type);
		lua_rawget(L, -2);

		/* check for function. */
		if(!lua_isnil(L, -1)) {
			/* pass cdata value to type checking function. */
			lua_pushvalue(L, _index);
			lua_call(L, 1, 1);
			if(!lua_isnil(L, -1)) {
				/* valid type get pointer from cdata. */
				lua_pop(L, 2);
				return (void *)lua_topointer(L, _index);
			}
		}
	}
	luaL_typerror(L, _index, type->name); /* is not a userdata value. */
	return NULL;
}

static FUNC_UNUSED void * obj_simple_udata_luaoptional(lua_State *L, int _index, obj_type *type) {
	if(lua_isnil(L, _index)) {
		return NULL;
	}
	return obj_simple_udata_luacheck(L, _index, type);
}

static FUNC_UNUSED void * obj_simple_udata_luadelete(lua_State *L, int _index, obj_type *type) {
	void *obj;
	obj = obj_simple_udata_luacheck(L, _index, type);
	/* clear the metatable to invalidate userdata. */
	lua_pushnil(L);
	lua_setmetatable(L, _index);
	return obj;
}

static FUNC_UNUSED void *obj_simple_udata_luapush(lua_State *L, void *obj, int size, obj_type *type)
{
	void *ud;
#if LUAJIT_FFI
	lua_pushlightuserdata(L, type);
	lua_rawget(L, LUA_REGISTRYINDEX); /* type's metatable. */
	if(nobj_ffi_support_enabled_hint && lua_isfunction(L, -1)) {
		/* call special FFI "void *" to FFI object convertion function. */
		lua_pushlightuserdata(L, obj);
		lua_call(L, 1, 1);
		return obj;
	}
#endif
	/* create new userdata. */
	ud = lua_newuserdata(L, size);
	memcpy(ud, obj, size);
	/* get obj_type metatable. */
#if LUAJIT_FFI
	lua_insert(L, -2); /* move userdata below metatable. */
#else
	lua_pushlightuserdata(L, type);
	lua_rawget(L, LUA_REGISTRYINDEX); /* type's metatable. */
#endif
	lua_setmetatable(L, -2);

	return ud;
}

/* default simple object equal method. */
static FUNC_UNUSED int obj_simple_udata_default_equal(lua_State *L) {
	void *ud1 = obj_simple_udata_toobj(L, 1);
	size_t len1 = lua_objlen(L, 1);
	void *ud2 = obj_simple_udata_toobj(L, 2);
	size_t len2 = lua_objlen(L, 2);

	if(len1 == len2) {
		lua_pushboolean(L, (memcmp(ud1, ud2, len1) == 0));
	} else {
		lua_pushboolean(L, 0);
	}
	return 1;
}

/* default simple object tostring method. */
static FUNC_UNUSED int obj_simple_udata_default_tostring(lua_State *L) {
	void *ud = obj_simple_udata_toobj(L, 1);

	/* get object's metatable. */
	lua_getmetatable(L, 1);
	lua_remove(L, 1); /* remove userdata. */
	/* get the object's name from the metatable */
	lua_getfield(L, 1, ".name");
	lua_remove(L, 1); /* remove metatable */
	/* push object's pointer */
	lua_pushfstring(L, ": %p", ud);
	lua_concat(L, 2);

	return 1;
}

static int obj_constructor_call_wrapper(lua_State *L) {
	/* replace '__call' table with constructor function. */
	lua_pushvalue(L, lua_upvalueindex(1));
	lua_replace(L, 1);

	/* call constructor function with all parameters after the '__call' table. */
	lua_call(L, lua_gettop(L) - 1, LUA_MULTRET);
	/* return all results from constructor. */
	return lua_gettop(L);
}

static void obj_type_register_constants(lua_State *L, const obj_const *constants, int tab_idx,
		int bidirectional) {
	/* register constants. */
	while(constants->name != NULL) {
		lua_pushstring(L, constants->name);
		switch(constants->type) {
		case CONST_BOOLEAN:
			lua_pushboolean(L, constants->num != 0.0);
			break;
		case CONST_NUMBER:
			lua_pushnumber(L, constants->num);
			break;
		case CONST_STRING:
			lua_pushstring(L, constants->str);
			break;
		default:
			lua_pushnil(L);
			break;
		}
		/* map values back to keys. */
		if(bidirectional) {
			/* check if value already exists. */
			lua_pushvalue(L, -1);
			lua_rawget(L, tab_idx - 3);
			if(lua_isnil(L, -1)) {
				lua_pop(L, 1);
				/* add value->key mapping. */
				lua_pushvalue(L, -1);
				lua_pushvalue(L, -3);
				lua_rawset(L, tab_idx - 4);
			} else {
				/* value already exists. */
				lua_pop(L, 1);
			}
		}
		lua_rawset(L, tab_idx - 2);
		constants++;
	}
}

static void obj_type_register_package(lua_State *L, const reg_sub_module *type_reg) {
	const luaL_reg *reg_list = type_reg->pub_funcs;

	/* create public functions table. */
	if(reg_list != NULL && reg_list[0].name != NULL) {
		/* register functions */
		luaL_register(L, NULL, reg_list);
	}

	obj_type_register_constants(L, type_reg->constants, -1, type_reg->bidirectional_consts);

	lua_pop(L, 1);  /* drop package table */
}

static void obj_type_register_meta(lua_State *L, const reg_sub_module *type_reg) {
	const luaL_reg *reg_list;

	/* create public functions table. */
	reg_list = type_reg->pub_funcs;
	if(reg_list != NULL && reg_list[0].name != NULL) {
		/* register functions */
		luaL_register(L, NULL, reg_list);
	}

	obj_type_register_constants(L, type_reg->constants, -1, type_reg->bidirectional_consts);

	/* register methods. */
	luaL_register(L, NULL, type_reg->methods);

	/* create metatable table. */
	lua_newtable(L);
	luaL_register(L, NULL, type_reg->metas); /* fill metatable */
	/* setmetatable on meta-object. */
	lua_setmetatable(L, -2);

	lua_pop(L, 1);  /* drop meta-object */
}

static void obj_type_register(lua_State *L, const reg_sub_module *type_reg, int priv_table) {
	const luaL_reg *reg_list;
	obj_type *type = type_reg->type;
	const obj_base *base = type_reg->bases;

	if(type_reg->req_type == REG_PACKAGE) {
		obj_type_register_package(L, type_reg);
		return;
	}
	if(type_reg->req_type == REG_META) {
		obj_type_register_meta(L, type_reg);
		return;
	}

	/* create public functions table. */
	reg_list = type_reg->pub_funcs;
	if(reg_list != NULL && reg_list[0].name != NULL) {
		/* register "constructors" as to object's public API */
		luaL_register(L, NULL, reg_list); /* fill public API table. */

		/* make public API table callable as the default constructor. */
		lua_newtable(L); /* create metatable */
		lua_pushliteral(L, "__call");
		lua_pushcfunction(L, reg_list[0].func); /* push first constructor function. */
		lua_pushcclosure(L, obj_constructor_call_wrapper, 1); /* make __call wrapper. */
		lua_rawset(L, -3);         /* metatable.__call = <default constructor> */

#if OBJ_DATA_HIDDEN_METATABLE
		lua_pushliteral(L, "__metatable");
		lua_pushboolean(L, 0);
		lua_rawset(L, -3);         /* metatable.__metatable = false */
#endif

		/* setmetatable on public API table. */
		lua_setmetatable(L, -2);

		lua_pop(L, 1); /* pop public API table, don't need it any more. */
		/* create methods table. */
		lua_newtable(L);
	} else {
		/* register all methods as public functions. */
#if OBJ_DATA_HIDDEN_METATABLE
		lua_pop(L, 1); /* pop public API table, don't need it any more. */
		/* create methods table. */
		lua_newtable(L);
#endif
	}

	luaL_register(L, NULL, type_reg->methods); /* fill methods table. */

	luaL_newmetatable(L, type->name); /* create metatable */
	lua_pushliteral(L, ".name");
	lua_pushstring(L, type->name);
	lua_rawset(L, -3);    /* metatable['.name'] = "<object_name>" */
	lua_pushliteral(L, ".type");
	lua_pushlightuserdata(L, type);
	lua_rawset(L, -3);    /* metatable['.type'] = lightuserdata -> obj_type */
	lua_pushlightuserdata(L, type);
	lua_pushvalue(L, -2); /* dup metatable. */
	lua_rawset(L, LUA_REGISTRYINDEX);    /* REGISTRY[type] = metatable */

	/* add metatable to 'priv_table' */
	lua_pushstring(L, type->name);
	lua_pushvalue(L, -2); /* dup metatable. */
	lua_rawset(L, priv_table);    /* priv_table["<object_name>"] = metatable */

	luaL_register(L, NULL, type_reg->metas); /* fill metatable */

	/* add obj_bases to metatable. */
	while(base->id >= 0) {
		lua_pushlightuserdata(L, (void *)base);
		lua_rawseti(L, -2, base->id);
		base++;
	}

	obj_type_register_constants(L, type_reg->constants, -2, type_reg->bidirectional_consts);

	lua_pushliteral(L, "__index");
	lua_pushvalue(L, -3);               /* dup methods table */
	lua_rawset(L, -3);                  /* metatable.__index = methods */
#if OBJ_DATA_HIDDEN_METATABLE
	lua_pushliteral(L, "__metatable");
	lua_pushboolean(L, 0);
	lua_rawset(L, -3);                  /* hide metatable:
	                                       metatable.__metatable = false */
#endif
	lua_pop(L, 2);                      /* drop metatable & methods */
}

static FUNC_UNUSED int lua_checktype_ref(lua_State *L, int _index, int _type) {
	luaL_checktype(L,_index,_type);
	lua_pushvalue(L,_index);
	return luaL_ref(L, LUA_REGISTRYINDEX);
}

]]

-- templates for typed *_check/*_delete/*_push macros.
local obj_type_check_delete_push = {
['simple'] = [[
#define obj_type_${object_name}_check(L, _index) \
	*((${object_name} *)obj_simple_udata_luacheck(L, _index, &(obj_type_${object_name})))
#define obj_type_${object_name}_optional(L, _index) \
	*((${object_name} *)obj_simple_udata_luaoptional(L, _index, &(obj_type_${object_name})))
#define obj_type_${object_name}_delete(L, _index) \
	*((${object_name} *)obj_simple_udata_luadelete(L, _index, &(obj_type_${object_name})))
#define obj_type_${object_name}_push(L, obj) \
	obj_simple_udata_luapush(L, &(obj), sizeof(${object_name}), &(obj_type_${object_name}))
]],
['simple ptr'] = [[
#define obj_type_${object_name}_check(L, _index) \
	*((${object_name} **)obj_simple_udata_luacheck(L, _index, &(obj_type_${object_name})))
#define obj_type_${object_name}_optional(L, _index) \
	*((${object_name} **)obj_simple_udata_luaoptional(L, _index, &(obj_type_${object_name})))
#define obj_type_${object_name}_delete(L, _index) \
	*((${object_name} **)obj_simple_udata_luadelete(L, _index, &(obj_type_${object_name})))
#define obj_type_${object_name}_push(L, obj) \
	obj_simple_udata_luapush(L, &(obj), sizeof(${object_name}), &(obj_type_${object_name}))
]],
['embed'] = [[
#define obj_type_${object_name}_check(L, _index) \
	(${object_name} *)obj_simple_udata_luacheck(L, _index, &(obj_type_${object_name}))
#define obj_type_${object_name}_optional(L, _index) \
	(${object_name} *)obj_simple_udata_luaoptional(L, _index, &(obj_type_${object_name}))
#define obj_type_${object_name}_delete(L, _index) \
	(${object_name} *)obj_simple_udata_luadelete(L, _index, &(obj_type_${object_name}))
#define obj_type_${object_name}_push(L, obj) \
	obj_simple_udata_luapush(L, obj, sizeof(${object_name}), &(obj_type_${object_name}))
]],
['object id'] = [[
#define obj_type_${object_name}_check(L, _index) \
	(${object_name})(uintptr_t)obj_udata_luacheck(L, _index, &(obj_type_${object_name}))
#define obj_type_${object_name}_optional(L, _index) \
	(${object_name})(uintptr_t)obj_udata_luaoptional(L, _index, &(obj_type_${object_name}))
#define obj_type_${object_name}_delete(L, _index, flags) \
	(${object_name})(uintptr_t)obj_udata_luadelete(L, _index, &(obj_type_${object_name}), flags)
#define obj_type_${object_name}_push(L, obj, flags) \
	obj_udata_luapush(L, (void *)((uintptr_t)obj), &(obj_type_${object_name}), flags)
]],
['generic'] = [[
#define obj_type_${object_name}_check(L, _index) \
	obj_udata_luacheck(L, _index, &(obj_type_${object_name}))
#define obj_type_${object_name}_optional(L, _index) \
	obj_udata_luaoptional(L, _index, &(obj_type_${object_name}))
#define obj_type_${object_name}_delete(L, _index, flags) \
	obj_udata_luadelete(L, _index, &(obj_type_${object_name}), flags)
#define obj_type_${object_name}_push(L, obj, flags) \
	obj_udata_luapush(L, obj, &(obj_type_${object_name}), flags)
]],
['generic_weak'] = [[
#define obj_type_${object_name}_check(L, _index) \
	obj_udata_luacheck(L, _index, &(obj_type_${object_name}))
#define obj_type_${object_name}_optional(L, _index) \
	obj_udata_luaoptional(L, _index, &(obj_type_${object_name}))
#define obj_type_${object_name}_delete(L, _index, flags) \
	obj_udata_luadelete_weak(L, _index, &(obj_type_${object_name}), flags)
#define obj_type_${object_name}_push(L, obj, flags) \
	obj_udata_luapush_weak(L, (void *)obj, &(obj_type_${object_name}), flags)
]],
}

-- prefix for default equal/tostring methods.
local obj_type_equal_tostring = {
['simple'] = 'obj_simple_udata_default',
['simple ptr'] = 'obj_simple_udata_default',
['embed'] = 'obj_simple_udata_default',
['object id'] = 'obj_udata_default',
['generic'] = 'obj_udata_default',
['generic_weak'] = 'obj_udata_default',
}

local create_object_instance_cache = [[
static void create_object_instance_cache(lua_State *L) {
	lua_pushlightuserdata(L, obj_udata_weak_ref_key); /* key for weak table. */
	lua_rawget(L, LUA_REGISTRYINDEX);  /* check if weak table exists already. */
	if(!lua_isnil(L, -1)) {
		lua_pop(L, 1); /* pop weak table. */
		return;
	}
	lua_pop(L, 1); /* pop nil. */
	/* create weak table for object instance references. */
	lua_pushlightuserdata(L, obj_udata_weak_ref_key); /* key for weak table. */
	lua_newtable(L);               /* weak table. */
	lua_newtable(L);               /* metatable for weak table. */
	lua_pushliteral(L, "__mode");
	lua_pushliteral(L, "v");
	lua_rawset(L, -3);             /* metatable.__mode = 'v'  weak values. */
	lua_setmetatable(L, -2);       /* add metatable to weak table. */
	lua_rawset(L, LUA_REGISTRYINDEX);  /* create reference to weak table. */
}

]]

local luaopen_main = [[
LUA_NOBJ_API int luaopen_${module_c_name}(lua_State *L) {
	const reg_sub_module *reg = reg_sub_modules;
	const luaL_Reg *submodules = submodule_libs;
	int priv_table = -1;

	/* private table to hold reference to object metatables. */
	lua_newtable(L);
	priv_table = lua_gettop(L);
	lua_pushlightuserdata(L, obj_udata_private_key);
	lua_pushvalue(L, priv_table);
	lua_rawset(L, LUA_REGISTRYINDEX);  /* store private table in registry. */

	/* create object cache. */
	create_object_instance_cache(L);

	/* module table. */
#if REG_MODULES_AS_GLOBALS
	luaL_register(L, "${module_name}", ${module_c_name}_function);
#else
	lua_newtable(L);
	luaL_register(L, NULL, ${module_c_name}_function);
#endif

	/* register module constants. */
	obj_type_register_constants(L, ${module_c_name}_constants, -1, 0);

	for(; submodules->func != NULL ; submodules++) {
		lua_pushcfunction(L, submodules->func);
		lua_pushstring(L, submodules->name);
		lua_call(L, 1, 0);
	}

	/* register objects */
	for(; reg->type != NULL ; reg++) {
		lua_newtable(L); /* create public API table for object. */
		lua_pushvalue(L, -1); /* dup. object's public API table. */
		lua_setfield(L, -3, reg->type->name); /* module["<object_name>"] = <object public API> */
#if REG_OBJECTS_AS_GLOBALS
		lua_pushvalue(L, -1);                 /* dup value. */
		lua_setglobal(L, reg->type->name);    /* global: <object_name> = <object public API> */
#endif
		obj_type_register(L, reg, priv_table);
	}

${module_init_src}

	return 1;
}
]]

local luaopen_submodule = [[
LUA_NOBJ_API int luaopen_${module_c_name}_${object_name}(lua_State *L) {
	const reg_sub_module *reg = &(submodule_${object_name}_reg);
	const luaL_Reg null_reg_list = { NULL, NULL };
	int priv_table = -1;

	/* private table to hold reference to object metatables. */
	lua_newtable(L);
	priv_table = lua_gettop(L);

	/* create object cache. */
	create_object_instance_cache(L);

	/* submodule table. */
#if REG_MODULES_AS_GLOBALS
	luaL_register(L, "${module_name}.${object_name}", &(null_reg_list));
#else
	lua_newtable(L);
	luaL_register(L, NULL, &(null_reg_list));
#endif

	/* register submodule. */
	lua_pushvalue(L, -1);   /* dup. submodule's table. */
	obj_type_register(L, reg, priv_table);
#if REG_OBJECTS_AS_GLOBALS
	lua_pushvalue(L, -1);            /* dup value. */
	lua_setglobal(L, reg->type->name);    /* global: <object_name> = <object public API> */
#endif

${module_init_src}

	return 1;
}

]]

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

local function add_constant(rec, constant)
	local const_type = nil
	local str = 'NULL'
	local num = '0.0'
	local value = constant.value
	local is_define = constant.is_define
	-- check the type of the constant's value.
	const_type = constant.vtype or type(value)
	if const_type == 'boolean' then
		const_type = 'CONST_BOOLEAN'
		if is_define then
			num = value
		else
			num = (value and '1.0' or '0.0')
		end
	elseif const_type == 'number' then
		const_type = 'CONST_NUMBER'
		if is_define then
			num = value
		else
			num = tostring(value)
		end
	elseif const_type == 'string' then
		const_type = 'CONST_STRING'
		if is_define then
			str = value
		else
			str = '"' .. value .. '"'
		end
	else
		-- un-supported type.
		const_type = nil
		value = nil
	end
	-- write constant.
	if const_type then
		if is_define then
			rec:write_part("const_regs", {
			'#ifdef ', value, '\n',
			'  {"', constant.name, '", ', str, ', ', num, ', ',const_type,'},\n',
			'#endif\n',
			})
		else
			rec:write_part("const_regs", {
			'  {"', constant.name, '", ', str, ', ', num, ', ',const_type,'},\n',
			})
		end
	end
end

local function add_field(rec, field)
end

local function gen_if_defs_code(rec)
	if rec.c_if_defs then return end
	-- generate #if code for if_defs.
	local if_defs = rec.if_defs
	local endif
	if type(if_defs) == 'string' then
		if_defs = "#if (" .. if_defs .. ')\n'
		endif = '#endif\n'
	elseif type(if_defs) == 'table' then
		if_defs = "#if (" .. table.concat(if_defs,"|") .. ')\n'
		endif = '#endif\n'
	else
		if_defs = ''
		endif = ''
	end
	rec.c_if_defs = if_defs
	rec.c_endif = endif
end

local function reg_object_function(self, func, object)
	local name = func.name
	local c_name = func.c_name
	local reg_list

	-- generate #if/#endif code
	gen_if_defs_code(func)

	-- check if this is object free/destructure method
	if func.is_destructor then
		-- add '__gc' method.
		if not self._cur_module.disable__gc and not object.disable__gc then
			object:write_part('metas_regs',
				{'  {"__gc", ', func.c_name, '},\n'})
		end
		if func._is_hidden then
			-- don't register '__gc' metamethods as a public object method.
			return '_priv', '__gc'
		end
		-- also register as a normal method.
		reg_list = object.methods_regs
	elseif func.is_constructor then
		reg_list = "pub_funcs_regs"
	elseif func._is_meta_method then
		reg_list = "metas_regs"
		-- use Lua's __* metamethod names
		name = lua_meta_methods[func.name]
	elseif func._is_method then
		reg_list = object.methods_regs
	else
		reg_list = object.functions_regs
	end
	-- add method to reg list.
	object:write_part(reg_list,
		{func.c_if_defs, '  {"', name, '", ', c_name, '},\n', func.c_endif})
	return name
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
	rec:add_var('nobj_realloc', rec.realloc or 'nobj_realloc')
	self._cur_module = rec
	self._modules_out[rec.name] = rec
	rec:write_part("typedefs", obj_udata_types)
	-- start obj_type array
	rec:write_part('obj_types',
		{'static obj_type obj_types[] = {\n'})
	-- start module/object register array.
	rec:write_part("reg_sub_modules",
		{'static const reg_sub_module reg_sub_modules[] = {\n'})
	-- start submodule_libs array
	rec:write_part("submodule_libs",
		{'static const luaL_Reg submodule_libs[] = {\n'})
	-- add create_object_instance_cache function.
	rec:write_part("luaopen", create_object_instance_cache)
	-- package_is_constructor?
	rec:write_part("defines",
		{'#define REG_PACKAGE_IS_CONSTRUCTOR ',(rec.package_is_constructor and 1 or 0),'\n'})
	-- module_globals?
	rec:write_part("defines",
		{'#define REG_MODULES_AS_GLOBALS ',(rec.module_globals and 1 or 0),'\n'})
	-- use_globals?
	rec:write_part("defines",
		{'#define REG_OBJECTS_AS_GLOBALS ',(rec.use_globals and 1 or 0),'\n'})
	-- hide_meta_info?
	if rec.hide_meta_info == nil then rec.hide_meta_info = true end
	rec:write_part("defines",
		{'#define OBJ_DATA_HIDDEN_METATABLE ',(rec.hide_meta_info and 1 or 0),'\n'})
	-- field access method: obj:field()/obj:set_field() or obj.field
	rec:write_part("defines",
		{'#define USE_FIELD_GET_SET_METHODS ',(rec.use_field_get_set_methods and 1 or 0),'\n'})
	-- where we want the module function registered.
	rec.functions_regs = 'function_regs'
	rec.methods_regs = 'function_regs'
	rec:write_part(rec.methods_regs,
		{'static const luaL_reg ${module_c_name}_function[] = {\n'})
end,
c_module_end = function(self, rec, parent)
	-- end obj_type array
	rec:write_part('obj_types',{
	'  {NULL, -1, 0, NULL},\n',
	'};\n'
	})
	-- end module/object register array.
	rec:write_part("reg_sub_modules", {
	'  {NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0}\n',
	'};\n\n'
	})
	-- end submodule_libs array
	rec:write_part("submodule_libs", {
	'  {NULL, NULL}\n',
	'};\n\n'
	})
	-- end function regs
	rec:write_part(rec.methods_regs, {
	'  {NULL, NULL}\n',
	'};\n\n'
	})
	-- build constants list
	rec:write_part("const_regs",
		{'static const obj_const ${module_c_name}_constants[] = {\n'})
	-- add constants
	for _,const in pairs(rec.constants) do
		add_constant(rec, const)
	end
	rec:write_part("const_regs", {
	'  {NULL, NULL, 0.0 , 0}\n',
	'};\n\n'
	})

	-- add main luaopen function.
	rec:add_var("module_init_src", rec:dump_parts{ "module_init_src"})
	rec:write_part("luaopen", luaopen_main)
	rec:write_part("helper_funcs", objHelperFunc)
	-- append extra source code.
	rec:write_part("extra_code", rec:dump_parts{ "src" })
	-- combine reg arrays into one part.
	local arrays = {
		"function_regs", "methods_regs", "metas_regs", "base_regs", "field_regs", "const_regs"}
	rec:write_part("reg_arrays", rec:dump_parts(arrays))
	-- apply variables to parts
	local parts = { "defines", "typedefs", "funcdefs", "reg_sub_modules", "submodule_regs",
		"submodule_libs", "helper_funcs", "extra_code", "methods", "reg_arrays", "luaopen_defs",
		"luaopen"}
	rec:vars_parts(parts)

	self._cur_module = nil
end,
error_code = function(self, rec, parent)
	rec:add_var('object_name', rec.name)
	local func_def = 'static void ' .. rec.func_name ..
		'(lua_State *L, ${object_name} err)'
	-- add push error function decl.
	rec:write_part('funcdefs', {
		'typedef ', rec.c_type, ' ${object_name};\n\n',
		func_def, ';\n'
	})
	-- start push error function.
	rec:write_part('src', {func_def, ' {\n'})
	-- add C variable for error string to be pushed.
	rec:write_part("src",
		{'  const char *err_str = NULL;\n'})
end,
error_code_end = function(self, rec, parent)
	-- push error value onto the stack.
	rec:write_part("src", [[
	if(err_str) {
		lua_pushstring(L, err_str);
	} else {
		lua_pushnil(L);
	}
}

]])
	-- append custom error push function.
	local parts = { "funcdefs", "src" }
	rec:vars_parts(parts)
	parent:copy_parts(rec, { "funcdefs" })
	-- append custom error push function.
	parent:write_part("methods", rec:dump_parts{ "src" })

end,
object = function(self, rec, parent)
	rec:add_var('object_name', rec.name)
	-- make luaL_reg arrays for this object
	if not rec.is_package then
		rec:write_part("metas_regs",
			{'static const luaL_reg obj_${object_name}_metas[] = {\n'})
		rec:write_part("base_regs",
			{'static const obj_base obj_${object_name}_bases[] = {\n'})
		rec:write_part("field_regs",
			{'static const obj_field obj_${object_name}_fields[] = {\n'})
		-- where we want the module function registered.
		rec.methods_regs = 'methods_regs'
		rec:write_part(rec.methods_regs,
			{'static const luaL_reg obj_${object_name}_methods[] = {\n'})
	elseif rec.is_meta then
		rec:write_part("metas_regs",
			{'static const luaL_reg obj_${object_name}_metas[] = {\n'})
		-- where we want the module function registered.
		rec.methods_regs = 'methods_regs'
		rec:write_part(rec.methods_regs,
			{'static const luaL_reg obj_${object_name}_methods[] = {\n'})
	end
	rec:write_part("const_regs",
		{'static const obj_const obj_${object_name}_constants[] = {\n'})
	rec.functions_regs = 'pub_funcs_regs'
	rec:write_part("pub_funcs_regs",
		{'static const luaL_reg obj_${object_name}_pub_funcs[] = {\n'})
end,
object_end = function(self, rec, parent)
	-- check for dyn_caster
	local dyn_caster = 'NULL'
	if rec.has_dyn_caster then
		dyn_caster = rec.has_dyn_caster.dyn_caster_name
	end
	-- create check/delete/push macros
	local ud_type = rec.userdata_type
	if not rec.no_weak_ref then
		ud_type = ud_type .. '_weak'
	end
	if not rec.is_package then
		rec:write_part("obj_check_delete_push", {
			rec.c_custom_check_delete_push or obj_type_check_delete_push[ud_type],
			'\n'
		})
	end
	-- object type flags
	local flags = {}
	if not rec.no_weak_ref then
		flags[#flags+1] = 'OBJ_TYPE_FLAG_WEAK_REF'
	end
	if ud_type == 'simple' or ud_type == 'simple ptr' or ud_type == 'embed' then
		flags[#flags+1] = 'OBJ_TYPE_SIMPLE'
	end
	if #flags > 0 then
		flags = table.concat(flags, '|')
	else
		flags = '0'
	end
	-- build obj_type info.
	rec:write_part('obj_types', {
	'#define obj_type_id_${object_name} ', rec._obj_id, '\n',
	'#define ', rec._obj_type_name, ' (obj_types[obj_type_id_${object_name}])\n',
	'  { ', dyn_caster, ', ', rec._obj_id , ', ',flags,', "${object_name}" },\n'
	})
	if not rec.is_package then
		-- check if object has a '__str__' method.
		if rec.functions['__str__'] == nil and rec.functions['__tostring'] == nil then
			rec:write_part('metas_regs',
				{'  {"__tostring", ',obj_type_equal_tostring[ud_type],'_tostring},\n'})
		end
		if rec.functions['__eq__'] == nil and rec.functions['__eq'] == nil then
			rec:write_part('metas_regs',
				{'  {"__eq", ',obj_type_equal_tostring[ud_type],'_equal},\n'})
		end
		-- finish luaL_reg arrays for this object
		rec:write_part("methods_regs", {
		'  {NULL, NULL}\n',
		'};\n\n'
		})
		rec:write_part("metas_regs", {
		'  {NULL, NULL}\n',
		'};\n\n'
		})
		rec:write_part("base_regs", {
		'  {-1, NULL}\n',
		'};\n\n'
		})
		-- add fields
		for _,field in pairs(rec.fields) do
			add_field(rec, field)
		end
		rec:write_part("field_regs", {
		'  {NULL, 0, 0, 0}\n',
		'};\n\n'
		})
	elseif rec.is_meta then
		-- finish luaL_reg arrays for this object
		rec:write_part("methods_regs", {
		'  {NULL, NULL}\n',
		'};\n\n'
		})
		rec:write_part("metas_regs", {
		'  {NULL, NULL}\n',
		'};\n\n'
		})
	end
	-- add constants
	for _,const in pairs(rec.constants) do
		add_constant(rec, const)
	end
	rec:write_part("const_regs", {
	'  {NULL, NULL, 0.0 , 0}\n',
	'};\n\n'
	})
	rec:write_part("pub_funcs_regs", {
	'  {NULL, NULL}\n',
	'};\n\n'
	})
	-- add obj_type to register array.
	local type_info_ptr = '&(' .. rec._obj_type_name .. ')'
	if rec.is_mod_global then
		type_info_ptr = 'NULL'
	end
	local object_reg_info
	local bidirectional = '0'
	if rec.map_constants_bidirectional then
		bidirectional = '1'
	end
	if rec.is_meta then
		object_reg_info = {
		'  { ', type_info_ptr, ', REG_META, obj_${object_name}_pub_funcs, obj_${object_name}_methods, ',
			'obj_${object_name}_metas, NULL, NULL, obj_${object_name}_constants, ',bidirectional,'}'
		}
	elseif rec.is_package then
		object_reg_info = {
		'  { ', type_info_ptr, ', REG_PACKAGE, obj_${object_name}_pub_funcs, NULL, ',
			'NULL, NULL, NULL, obj_${object_name}_constants, ',bidirectional,'}'
		}
	else
		object_reg_info = {
		'  { ', type_info_ptr, ', REG_OBJECT, obj_${object_name}_pub_funcs, ',
			'obj_${object_name}_methods, obj_${object_name}_metas, obj_${object_name}_bases, ',
			'obj_${object_name}_fields, obj_${object_name}_constants, ',bidirectional,'}'
		}
	end

	if rec.register_as_submodule then
		-- add submodule luaopen function.
		rec:add_var("module_init_src", rec:dump_parts{ "module_init_src"})
		rec:write_part("luaopen", luaopen_submodule)
		rec:write_part("luaopen_defs",
			"int luaopen_${module_c_name}_${object_name}(lua_State *L);\n")
		rec:write_part("submodule_libs",
			'  { "${module_c_name}.${object_name}", luaopen_${module_c_name}_${object_name} },\n')
		-- add submodule type info.
		rec:write_part("submodule_regs",
			"static const reg_sub_module submodule_${object_name}_reg =\n")
		rec:write_part("submodule_regs", object_reg_info)
		rec:write_part("submodule_regs", ";\n")
	else
		rec:write_part("reg_sub_modules", object_reg_info)
		rec:write_part("reg_sub_modules", ",\n")
	end
	-- append extra source code.
	rec:write_part("extra_code", rec:dump_parts{ "src" })
	-- combine reg arrays into one part.
	local arrays = {
		"function_regs", "pub_funcs_regs", "methods_regs", "metas_regs",
		"base_regs", "field_regs", "const_regs"
	}
	rec:write_part("reg_arrays", rec:dump_parts(arrays))
	-- apply variables to parts
	local parts = { "defines", "funcdefs", "methods", "obj_check_delete_push",
		"obj_types", "reg_arrays", "reg_sub_modules", "submodule_regs", "submodule_libs",
		"luaopen_defs", "luaopen", "extra_code" }
	rec:vars_parts(parts)
	-- copy parts to parent
	parent:copy_parts(rec, parts)

end,
callback_state = function(self, rec, parent)
	rec:add_var('wrap_type', rec.wrap_type)
	rec:add_var('base_type', rec.base_type)
	-- start callback object.
	rec:write_part("wrapper_obj",
	{'/* callback object: ', rec.name, ' */\n',
		'typedef struct {\n',
		'  ', rec.base_type, ' base;\n',
		'  lua_State *L;\n',
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
	local parts = {"funcdefs", "methods", "extra_code"}
	rec:vars_parts(parts)
	-- copy parts to parent
	parent:copy_parts(rec, parts)
end,
include = function(self, rec, parent)
	if self._includes[rec.file] then return end
	self._includes[rec.file] = true
	-- append include file
	if rec.is_system then
		self._cur_module:write_part("includes", { '#include <', rec.file, '>\n' })
	else
		self._cur_module:write_part("includes", { '#include "', rec.file, '"\n' })
	end
end,
define = function(self, rec, parent)
	-- append to defines parts
	if rec.value then
		self._cur_module:write_part("defines", { '#define ', rec.name, ' ', rec.value, '\n' })
	else
		self._cur_module:write_part("defines", { '#define ', rec.name, '\n' })
	end
end,
extends = function(self, rec, parent)
	assert(not parent.is_package, "A Package can't extend anything: package=" .. parent.name)
	local base = rec.base
	local base_cast = 'NULL'
	if base == nil then return end
	-- add methods/fields/constants from base object
	for name,val in pairs(base.name_map) do
		-- make sure sub-class has not override name.
		if parent.name_map[name] == nil or parent.name_map[name] == val then
			parent.name_map[name] = val
			if val._is_method and not val.is_constructor then
				parent.functions[name] = val
				-- register base class's method with sub class
				reg_object_function(self, val, parent)
			elseif val._rec_type == 'field' then
				parent.fields[name] = val
			elseif val._rec_type == 'const' then
				parent.constants[name] = val
			end
		end
	end
	-- base_caster: helper functions.
	local function base_caster_name(class_name, base_name)
		return 'base_cast_' .. class_name .. '_to_' .. base_name
	end
	local function create_base_caster(class_name, base_name)
		local base_cast = base_caster_name(class_name, base_name)
		local caster_def = 'static void ' .. base_cast .. '(void **obj)'
		-- add base_cast decl.
		parent:write_part('funcdefs', {caster_def, ';\n'})
		-- start base_cast function.
		rec:write_part('src', {caster_def, ' {\n'})
		return base_cast
	end
	local function build_chain_of_caster_calls(class_name, chain)
		local prev_class = class_name
		local caster_calls = {}
		for i=1,#chain do
			local caster = chain[i]
			local base_name = caster.base.name
			-- only need to call custom casters.
			if caster.cast_type ~= 'direct' then
				-- call caster function.
				table.insert(caster_calls,
					'\t' .. base_caster_name(prev_class, base_name) .. '(obj);\n')
			end
			prev_class = base_name
		end
		if #caster_calls > 0 then
			return table.concat(caster_calls)
		end
		return nil
	end
	local function create_chain_base_caster(class_name, chain)
		local end_caster = chain[#chain]
		local base = end_caster.base
		local chain_caster = build_chain_of_caster_calls(class_name, chain)
		local base_cast = 'NULL'
		if chain_caster ~= nil then
			-- create base caster for ancestor base class.
			base_cast = create_base_caster(class_name, base.name)
			-- end caster function.
			rec:write_part('src', {chain_caster,'}\n\n'})
		end
		-- write base record.
		parent:write_part("base_regs", {
		'  {', base._obj_id, ', ', base_cast, '},\n',
		})
	end
	-- add casters for all base-class's ancestors
	for name,extend in pairs(base.extends) do
		create_chain_base_caster(parent.name, { rec, extend })
	end
	-- check for custom base_cast function.
	if rec.cast_type == 'custom' then
		local cast_type = parent.name .. '_to_' .. base.name .. '_t'
		base_cast = create_base_caster(parent.name, base.name)
		-- start base_cast function.
		rec:add_var('in_obj', 'val.in')
		rec:add_var('in_obj_type', parent.c_type)
		rec:add_var('out_obj', 'val.out')
		rec:add_var('out_obj_type', base.c_type)
		rec:write_part('pre', {
			'typedef union {\n',
			'  void            *obj;\n',
			'  ${in_obj_type}  in;\n',
			'  ${out_obj_type} out;\n',
			'} ',cast_type,';\n',
		})
		rec:write_part('src', {
			'  ',cast_type,' val = { .obj = *obj};\n',
		})
	end
	-- write base record.
	parent:write_part("base_regs", {
	'  {', base._obj_id, ', ', base_cast, '},\n',
	})
end,
extends_end = function(self, rec, parent)
	if rec.cast_type == 'custom' then
		-- end caster function.
		rec:write_part('src', {
			'  *obj = val.obj;\n',
			'}\n\n'
		})
	end
	-- map in/out variables in c source.
	local parts = {"pre", "pre_src", "src", "post"}
	rec:vars_parts(parts)

	-- append custom base caster code
	parent:write_part("methods", rec:dump_parts(parts))
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
	  {'  int ', rec.ref_field, ';\n'})
end,
callback_func_end = function(self, rec, parent)
	local wrapped = rec.wrapped_var
	local wrap_type = parent.wrap_type .. ' *'
	rec:write_part("cb_head",
	{ '  ', wrap_type,' wrap = (',wrap_type,')${', wrapped.name,'};\n',
		'  lua_State *L = wrap->L;\n',
	})
	rec:write_part("vars", {'\n  ', rec:_push('wrap->' .. rec.ref_field),})
	-- call lua callback function.
	rec:write_part("pre_src", {
	'  if(lua_pcall(L, ', rec.cb_ins, ', ', rec.cb_outs , ', 0)) {\n',
	})
	-- get default for function return value.
	local ret_out = rec.ret_out
	local func_rc = ''
	if ret_out then
		func_rc = "${" .. ret_out.name .. "}"
	end
	rec:write_part("post_src", {
	'    fprintf(stdout, "CALLBACK Error: %s\\n", lua_tostring(L, -1));\n',
	'    lua_pop(L, 1);\n',
	'    return ', func_rc,';\n',
	'  }\n',
	})
	rec:write_part("post", {'  lua_pop(L, ', rec.cb_outs , ');\n'})
	-- get return value from lua function.
	if ret_out then
		rec:write_part("post", {'  return ${', ret_out.name , '};\n'})
	end
	-- map in/out variables in c source.
	local parts = {"cb_head", "vars", "params", "pre_src", "src", "post_src", "post"}
	rec:vars_parts(parts)
	rec:vars_parts('func_decl')

	rec:write_part("post", {'}\n\n'})
	parent:write_part('methods', rec:dump_parts(parts))
	parent:write_part('funcdefs', rec:dump_parts('func_decl'))
end,
dyn_caster = function(self, rec, parent)
	rec.dyn_caster_name = 'dyn_caster_' .. parent.name
	local caster_def = 'static void dyn_caster_${object_name}(void **obj, obj_type **type)'
	-- add caster decl.
	parent:write_part('funcdefs', {caster_def, ';\n'})
	-- start caster function.
	rec:write_part('src', {caster_def, ' {\n'})
end,
dyn_caster_end = function(self, rec, parent)
	-- append switch based caster function.
	if rec.caster_type == 'switch' then
		local selector = ''
		if rec.value_field then
			selector = 'base_obj->' .. rec.value_field
		elseif rec.value_function then
			selector = rec.value_function .. '(base_obj)'
		else
			error("Missing switch value for dynamic caster.")
		end
		rec:write_part('src', {
			'  ${object_name} * base_obj = (${object_name} *)*obj;\n',
			'  switch(', selector, ') {\n',
		})
		-- add cases for each sub-object type.
		for val,sub in pairs(rec.value_map) do
			rec:write_part('src', {
				'  case ', val, ':\n',
				'    *type = &(', sub._obj_type_name, ');\n',
				'    break;\n'
			})
		end
		rec:write_part('src', {
			'  default:\n',
			'    break;\n',
			'  }\n',
		})
	end
	rec:write_part('src', {'}\n\n'})
	-- append custom dyn caster code
	parent:write_part("methods", rec:dump_parts{ "src" })
end,
c_function = function(self, rec, parent)
	rec.pushed_values = 0 -- track number of values pushed onto the stack.
	rec:add_var('object_name', parent.name)
	rec:add_var('function_name', rec.name)
	if rec.is_destructor then
		rec.__gc = true -- mark as '__gc' method
	end

	-- register method/function with object.
	local name = reg_object_function(self, rec, parent)

	rec:write_part("pre",
	{'/* method: ', name, ' */\n', rec.c_if_defs,
		'static int ', rec.c_name, '(lua_State *L) {\n'})
	-- is this a wrapper function
	if rec.wrapper_obj then
		local wrap_type = rec.wrapper_obj.wrap_type
		rec:write_part("pre",
			{ '  ', wrap_type,' *wrap;\n',
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
				{'  wrap = (',wrap_type,' *)${this};\n'})
			for name,cb in pairs(callbacks) do
				rec:write_part("src",
					{'  luaL_unref(L, LUA_REGISTRYINDEX, wrap->', name,');\n'})
			end
			rec:write_part("post",
				{'  obj_type_free(', wrap_type, ', wrap);\n'})
		elseif rec.is_constructor then
			rec:write_part("pre",
				{
				'  obj_type_new(', wrap_type, ', wrap);\n',
				'  ${this} = &(wrap->base);\n',
				'  wrap->L = L;\n',
				})
		end
	end
	-- apply variable name replacing in generated code.
	local parts = {"pre", "pre_src", "src", "post"}
	rec:vars_parts(parts)

	local outs = rec.pushed_values
	rec:write_part("post",
		{'  return ', outs, ';\n',
		 '}\n', rec.c_endif, '\n'})

	-- finialize C function code.
	self._cur_module:write_part('methods', rec:dump_parts(parts))

end,
c_source = function(self, rec, parent)
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

	local var_type = rec.c_type_rec
	if rec.is_this and parent.__gc then
		if var_type.has_obj_flags then
			-- add flags ${var_name_flags} variable
			parent:add_rec_var(rec, rec.name .. '_flags')
			local flags = '${' .. rec.name .. '_flags}'
			-- for garbage collect method, check the ownership flag before freeing 'this' object.
			parent:write_part("pre",
				{
				'  int ',flags,' = 0;\n',
				'  ', rec.c_type, var_type:_delete(rec, '&(' .. flags .. ')'),
				})
			parent:write_part("pre_src", {
				'  if(!(',flags,' & OBJ_UDATA_FLAG_OWN)) { return 0; }\n',
				})
		else
			-- for garbage collect method, check the ownership flag before freeing 'this' object.
			parent:write_part("pre",
				{
				'  ', rec.c_type, var_type:_delete(rec, false),
				})
		end
	elseif var_type._rec_type ~= 'callback_func' then
		if var_type.lang_type == 'string' then
			-- add length ${var_name_len} variable
			parent:add_rec_var(rec, rec.name .. '_len')
			-- add a variable to top of function for string's length.
			parent:write_part("pre",{
				'  size_t ${', rec.name ,'_len};\n'
			})
		end
		-- check lua value matches type.
		local get
		if rec.is_optional then
			get = var_type:_opt(rec, rec.default)
		else
			get = var_type:_check(rec)
		end
		parent:write_part("pre",
			{'  ', rec.c_type, get })
	end
	-- is a lua reference.
	if var_type.is_ref then
		parent:add_var(rec.name, rec.cb_func.c_func_name)
		parent:write_part("src",
			{'  wrap->', var_type.ref_field, ' = ',var_type:_check(rec) })
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
			parent:write_part("pre",{
				'  int ',flags,' = OBJ_UDATA_FLAG_OWN;\n'
			})
		else
			flags = "0"
		end
	end
	-- register variable for code gen (i.e. so ${var_name} is replaced with true variable name).
	parent:add_rec_var(rec)
	-- don't generate code for '<any>' type parameters
	if rec.c_type == '<any>' then
		parent.pushed_values = parent.pushed_values + 1
		return
	end

	local var_type = rec.c_type_rec
	if var_type.lang_type == 'string' and rec.has_length then
		-- add length ${var_name_len} variable
		parent:add_rec_var(rec, rec.name .. '_len')
		-- the C code will provide the string's length.
		parent:write_part("pre",{
			'  size_t ${', rec.name ,'_len} = 0;\n'
		})
	end
	-- if the variable's type has a default value, then initialize the variable.
	local init = ''
	if var_type.default then
		init = ' = ' .. tostring(var_type.default)
	elseif var_type.userdata_type == 'embed' then
		parent:write_part("pre",
			{'  ', var_type.name, ' ${', rec.name, '}_store;\n'})
		init = ' = &(${' .. rec.name .. '}_store)'
	end
	-- add C variable to hold value to be pushed.
	parent:write_part("pre",
		{'  ', rec.c_type, ' ${', rec.name, '}', init, ';\n'})
	-- if this is a temp. variable, then we are done.
	if rec.is_temp then
		return
	end
	-- push Lua value onto the stack.
	local push_count = 1
	local error_code = parent._has_error_code
	if error_code == rec then
		local err_type = error_code.c_type_rec
		-- if error_code is the first var_out, then push 'true' to signal no error.
		-- On error push 'false' and the error message.
		if rec._rec_idx == 1 then
			push_count = 2
			parent:write_part("post", {
			'  /* check for error. */\n',
			'  if(',err_type.is_error_check(error_code),') {\n',
			'    lua_pushnil(L);\n',
			'    ', var_type:_push(rec, flags),
			'  } else {\n',
			'    lua_pushboolean(L, 1);\n',
			'    lua_pushnil(L);\n',
			'  }\n',
			})
		else
			parent:write_part("post", { var_type:_push(rec, flags) })
		end
	elseif rec.no_nil_on_error ~= true and error_code then
		local err_type = error_code.c_type_rec
		-- return nil for this out variable, if there was an error.
		parent:write_part("post", {
		'  if(!',err_type.is_error_check(error_code),') {\n',
		'  ', var_type:_push(rec, flags),
		'  } else {\n',
		'    lua_pushnil(L);\n',
		'  }\n',
		})
	elseif rec.is_error_on_null then
		-- if a function return NULL, then there was an error.
		parent:write_part("post", {
		'  if(',var_type.is_error_check(rec),') {\n',
		'    lua_pushnil(L);\n',
		'  ', var_type:_push_error(rec),
		'  } else {\n',
		'  ', var_type:_push(rec, flags),
		'  }\n',
		})
	else
		parent:write_part("post", { var_type:_push(rec, flags) })
	end
	parent.pushed_values = parent.pushed_values + push_count
end,
cb_in = function(self, rec, parent)
	parent:add_rec_var(rec)
	local var_type = rec.c_type_rec
	if not rec.is_wrapped_obj then
		parent:write_part("params", { var_type:_push(rec) })
		parent.cb_ins = parent.cb_ins + 1
	else
		-- this is the wrapped object parameter.
		parent.wrapped_var = rec
	end
end,
cb_out = function(self, rec, parent)
	parent:add_rec_var(rec, 'ret', 'ret', -1)
	parent.cb_outs = parent.cb_outs + 1
	local var_type = rec.c_type_rec
	parent:write_part("vars",
		{'  ', rec.c_type, ' ${', rec.name, '} = ', var_type.default,';\n'})
	parent:write_part("post",
		{'  ', var_type:_to(rec) })
end,
}

local src_file=open_outfile('.c')
local function src_write(...)
	src_file:write(...)
end

-- write header
src_write(generated_output_header)

-- write includes
src_write[[
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

]]
for name,mod in pairs(parsed._modules_out) do
	src_write(
		mod:dump_parts({
			"defines",
			"includes",
			"typedefs",
			"funcdefs",
			"obj_types",
			"helper_funcs",
			"obj_check_delete_push",
			"extra_code",
			"methods",
			"reg_arrays",
			"reg_sub_modules",
			"submodule_regs",
			"luaopen_defs",
			"submodule_libs",
			"luaopen"
			}, "\n\n")
	)
end

print("Finished generating Lua bindings")

