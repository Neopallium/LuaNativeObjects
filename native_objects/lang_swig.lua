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
basetype "bool"           "boolean"

basetype "char"           "integer"
basetype "unsigned char"  "integer"
basetype "short"          "integer"
basetype "unsigned short" "integer"
basetype "int"            "integer"
basetype "unsigned int"   "integer"
basetype "long"           "integer"
basetype "unsigned long"  "integer"
-- stdint types.
basetype "int8_t"         "integer"
basetype "int16_t"        "integer"
basetype "int32_t"        "integer"
basetype "int64_t"        "integer"
basetype "uint8_t"        "integer"
basetype "uint16_t"       "integer"
basetype "uint32_t"       "integer"
basetype "uint64_t"       "integer"

basetype "float"          "number"
basetype "double"         "number"

basetype "char *"         "string"
basetype "void *"         "lightuserdata"
basetype "void"           "nil"

local lua_base_types = {
	['nil'] = { push = 'lua_pushnil' },
	['number'] = { to = 'lua_tonumber', check = 'luaL_checknumber', push = 'lua_pushnumber' },
	['integer'] = { to = 'lua_tointeger', check = 'luaL_checkinteger', push = 'lua_pushinteger' },
	['string'] = { to = 'lua_tostring', check = 'luaL_checkstring', push = 'lua_pushstring' },
	['boolean'] = { to = 'lua_toboolean', check = 'lua_toboolean', push = 'lua_pushboolean' },
	['lightuserdata'] =
		{ to = 'lua_touserdata', check = 'lua_touserdata', push = 'lua_pushlightuserdata' },
}

