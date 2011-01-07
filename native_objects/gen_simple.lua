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
-- dump info
--
--[[
print"============ Dump types ================="
for k,v in pairs(types) do
	local lang_type = v.lang_type
	if lang_type == nil then
		lang_type = 'userdata'
	end
	print(v.c_type .. '\t(' .. k .. ')' .. '\tlua: ' .. lang_type)
end
]]
print"============ Dump objects ================="
local function find_ret(rec)
	for i,v in ipairs(rec) do
		if is_record(v) and v._rec_type == 'var_out' then
			return v;
		end
	end
	return { c_type = "void" }
end
process_records{
object = function(self, rec, parent)
	print("object " .. rec.name .. "{")
	--print(dump(rec))
end,
property = function(self, rec, parent)
	print(rec.c_type .. " " .. rec.name .. "; /* is='" .. rec.is .. "', isa='" .. rec.isa .. "' */")
end,
include = function(self, rec, parent)
	print('#include "' .. rec.file .. '"')
end,
option = function(self, rec, parent)
	print("/* option: " .. rec.name .. " */")
end,
object_end = function(self, rec, parent)
	print("}\n")
end,
c_function = function(self, rec, parent)
	local ret = find_ret(rec)
	io.write(ret.c_type .. " " .. rec.name .. "(")
end,
c_function_end = function(self, rec, parent)
	print(")")
end,
var_in = function(self, rec, parent)
	if parent._first_var ~= nil then
		io.write(', ')
	else
		parent._first_var = true
	end
	io.write(rec.c_type .. " " .. rec.name)
end,
}

