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

dottify = require"dotlua"
require"utils"

--
-- dump records
--
print"============ Dump records ================="

local root = {}
local function parent_add_child(parent, child, name)
	if parent == nil then return {} end
	local info = parent.info
	if info == nil then info = {}; parent.info = info end
	if name == nil then name = #info + 1 end
	info[name] = child
	return child
end
local objects = {}

process_records{
c_module_end = function(self, rec, parent)
	root = rec.info
end,
object = function(self, rec, parent)
	local info = parent_add_child(parent, {})
	objects[rec.name] = info
	info[1] = rec._rec_type
	info[2] = rec.name
	info[3] = "=========================="
	rec.info = info
end,
extends = function(self, rec, parent)
	parent.info.extends = objects[rec.name]
end,
c_function = function(self, rec, parent)
	rec.params = ''
end,
c_function_end = function(self, rec, parent)
	local ret_type = rec.ret_type or "void"
	local func = ret_type .. " " .. rec.name .. "(" .. rec.params .. ")"
	parent_add_child(parent, func)
end,
var_out = function(self, rec, parent)
	parent.ret_type = rec.c_type
end,
var_in = function(self, rec, parent)
	if parent._first_var ~= nil then
		parent.params = parent.params .. ', '
	else
		parent._first_var = true
	end
	parent.params = parent.params .. rec.c_type .. " " .. rec.name
end,
--[=[
unknown = function(self, rec, parent)
	local info = parent_add_child(parent)
	info[1] = rec._rec_type
	rec.info = info
end,
--[=[
c_module = function(self, rec, parent)
	root = rec
end,
unknown = function(self, rec, parent)
	rec._rec_idx = nil
	rec._parent = nil
	rec._symbol_map = nil
	rec._data_parts = nil
	rec._imports = nil
	rec._vars = nil
	rec.functions = nil
	rec.src = nil
	rec.subs = nil
end,
--]=]
}

print(dump(root))
dottify(get_outfile_name(".dot"), root, "nometatables", "noupvalues", "values")

