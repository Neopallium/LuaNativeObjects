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
-- C to Lua Base types
--
basetype "bool"           "boolean" "0"

basetype "char"           "integer" "0"
basetype "unsigned char"  "integer" "0"
basetype "short"          "integer" "0"
basetype "unsigned short" "integer" "0"
basetype "int"            "integer" "0"
basetype "unsigned"       "integer" "0"
basetype "unsigned int"   "integer" "0"
basetype "long"           "integer" "0"
basetype "unsigned long"  "integer" "0"
-- stdint types.
basetype "int8_t"         "integer" "0"
basetype "int16_t"        "integer" "0"
basetype "int32_t"        "integer" "0"
basetype "int64_t"        "integer" "0"
basetype "uint8_t"        "integer" "0"
basetype "uint16_t"       "integer" "0"
basetype "uint32_t"       "integer" "0"
basetype "uint64_t"       "integer" "0"
basetype "size_t"         "integer" "0"
basetype "ssize_t"        "integer" "0"
basetype "off_t"          "integer" "0"
basetype "time_t"         "integer" "0"

basetype "float"          "number" "0.0"
basetype "double"         "number" "0.0"

basetype "char *"         "string" "NULL"
basetype "unsigned char *" "string" "NULL"
basetype "void *"         "lightuserdata" "NULL"
basetype "lua_State *"    "thread" "NULL"
basetype "void"           "nil" "NULL"

basetype "<any>"          "nil" "NULL"

--
-- to/check/push/delete methods
--
print"============ create Lua to/check/push/delete methods ================="
local lua_base_types = {
	['nil'] = { push = 'lua_pushnil' },
	['number'] = { to = 'lua_tonumber', opt = 'luaL_optnumber', check = 'luaL_checknumber',
		push = 'lua_pushnumber' },
	['integer'] = { to = 'lua_tointeger', opt = 'luaL_optinteger', check = 'luaL_checkinteger',
		push = 'lua_pushinteger' },
	['string'] = { to = 'lua_tolstring', opt = 'luaL_optlstring', check = 'luaL_checklstring',
		push = 'lua_pushstring', push_len = 'lua_pushlstring' },
	['boolean'] = { to = 'lua_toboolean', check = 'lua_toboolean', push = 'lua_pushboolean' },
	['thread'] = { to = 'lua_tothread', check = 'lua_tothread', push = 'lua_pushthread' },
	['lightuserdata'] =
		{ to = 'lua_touserdata', check = 'lua_touserdata', push = 'lua_pushlightuserdata' },
}

process_records{
	basetype = function(self, rec, parent)
		local l_type = lua_base_types[rec.lang_type]
		if l_type ~= nil then
			rec._ffi_push = function(self, var)
				local wrap = var.ffi_wrap
				if wrap then
					return wrap .. '(${' .. var.name .. '})\n'
				else
					return '${' .. var.name .. '}\n'
				end
			end
			if rec.lang_type == 'string' then
				rec._to = function(self, var)
					return ' ${' .. var.name .. '} = ' ..
						l_type.to .. '(L,${' .. var.name .. '::idx},&(${' .. var.name .. '_len}));\n'
				end
				rec._check = function(self, var)
					return ' ${' .. var.name .. '} = ' ..
						l_type.check .. '(L,${' .. var.name .. '::idx},&(${' .. var.name .. '_len}));\n'
				end
				rec._opt = function(self, var, default)
					if default then
						default = '"' .. default .. '"'
					else
						default = 'NULL'
					end
					return ' ${' .. var.name .. '} = ' ..
						l_type.opt .. '(L,${' .. var.name .. '::idx},' .. default ..
						',&(${' .. var.name .. '_len}));\n'
				end
				rec._push = function(self, var)
					if var.has_length then
						return
						'  if(${' .. var.name .. '} == NULL) lua_pushnil(L);' ..
						'  else ' .. l_type.push_len .. '(L, ${' .. var.name .. '},' ..
						                                    '${' .. var.name .. '_len});\n'
					end
					return '  ' .. l_type.push .. '(L, ${' .. var.name .. '});\n'
				end
				rec._ffi_push = function(self, var)
					if var.has_length then
						return
						'((nil ~= ${' .. var.name .. '}) and ' ..
						'ffi.string(${' .. var.name .. '},${' .. var.name .. '_len}))\n'
					end
					return '((nil ~= ${' .. var.name .. '}) and ffi.string(${' .. var.name .. '}))\n'
				end
				rec._ffi_check = function(self, var)
					return 'local ${' .. var.name .. '_len} = #${' .. var.name .. '}\n'
				end
				rec._ffi_opt = function(self, var, default)
					if default then
						default = (' or %q'):format(tostring(default))
					else
						default = ''
					end
					return 
						'${' .. var.name .. '} = ${' .. var.name .. '}' .. default .. '\n' ..
						'  local ${' .. var.name .. '_len} = #${' .. var.name .. '}\n'
				end
			else
				rec._to = function(self, var)
					return ' ${' .. var.name .. '} = ' .. l_type.to .. '(L,${' .. var.name .. '::idx});\n'
				end
				rec._check = function(self, var)
					return ' ${' .. var.name .. '} = ' .. l_type.check .. '(L,${' .. var.name .. '::idx});\n'
				end
				rec._opt = function(self, var, default)
					default = default or '0'
					if l_type.opt then
						return ' ${' .. var.name .. '} = ' ..
							l_type.opt .. '(L,${' .. var.name .. '::idx},' .. default .. ');\n'
					end
					return ' ${' .. var.name .. '} = ' ..
						l_type.to .. '(L,${' .. var.name .. '::idx});\n'
				end
				rec._push = function(self, var)
					return '  ' .. l_type.push .. '(L, ${' .. var.name .. '});\n'
				end
				rec._ffi_check = function(self, var)
					return '\n'
				end
				rec._ffi_opt = function(self, var, default)
					default = tostring(default or '0')
					return 
						'  ${' .. var.name .. '} = ${' .. var.name .. '} or ' .. default .. '\n'
				end
			end
		end
	end,
	error_code = function(self, rec, parent)
		local func_name = 'error_code__' .. rec.name .. '__push'
		rec.func_name = func_name

		-- create _push_error & _push function
		rec._push = function(self, var)
			return '  ' .. func_name ..'(L, ${' .. var.name .. '});\n'
		end
		rec._push_error = rec._push
		rec._ffi_push = function(self, var)
			return '  ' .. func_name ..'(${' .. var.name .. '})\n'
		end
		rec._ffi_push_error = rec._ffi_push
	end,
	object = function(self, rec, parent)
		rec.lang_type = 'userdata'
		local type_name = 'obj_type_' .. rec.name
		rec._obj_type_name = type_name

		-- create _check/_delete/_push functions
		rec._check = function(self, var)
			return ' ${'..var.name..'} = '..type_name..'_check(L,${'..var.name..'::idx});\n'
		end
		rec._opt = function(self, var)
			return ' ${'..var.name..'} = '..type_name..'_optional(L,${'..var.name..'::idx});\n'
		end
		rec._delete = function(self, var, flags)
			assert(flags, 'need flags variable')
			return ' ${'..var.name..'} = '..type_name..'_delete(L,${'..var.name..'::idx},'..flags..');\n'
		end
		rec._to = rec._check
		rec._push = function(self, var, own)
			if own == nil then own = '0' end
			return '  '..type_name..'_push(L, ${'..var.name..'}, '..own..');\n'
		end
		rec._ffi_check = function(self, var)
			if var.is_this then
				return 'local ${' .. var.name .. '} = '..type_name..'_check(self)\n'
			end
			local name = '${' .. var.name .. '}'
			return '' .. name .. ' = '..type_name..'_check('..name..')\n'
		end
		rec._ffi_opt = function(self, var)
			if var.is_this then
				return 'local ${' .. var.name .. '} = '..type_name..'_check(self)\n'
			end
			local name = '${' .. var.name .. '}'
			return '' .. name .. ' = '..name..' and '..type_name..'_check('..name..') or nil\n'
		end
		rec._ffi_delete = function(self, var)
			return 'local ${'..var.name..'},${'..var.name..'_flags} = '..type_name..'_delete(self)\n'
		end
		rec._ffi_push = function(self, var, own)
			if own == nil then own = '0' end
			return '  '..type_name..'_push(${'..var.name..'}, '..own..')\n'
		end
		if rec.error_on_null then
			rec._push_error = function(self, var)
				return '  lua_pushstring(L, ' .. rec.error_on_null .. ');\n'
			end
			rec._ffi_push_error = function(self, var)
				return '  ' .. rec.error_on_null .. '\n'
			end
		end
	end,
	callback_func = function(self, rec, parent)
		rec.lang_type = 'function'

		-- create _check/_delete/_push functions
		rec._check = function(self, var)
			return 'lua_checktype_ref(L, ${' .. var.name .. '::idx}, LUA_TFUNCTION);\n'
		end
		rec._delete = nil
		rec._to = rec._check
		rec._push = function(self, var)
			return 'lua_rawgeti(L, LUA_REGISTRYINDEX, ' .. var .. ');\n'
		end
	end,
}

