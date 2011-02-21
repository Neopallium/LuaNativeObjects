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

local tinsert,tremove=table.insert,table.remove
local tappend=function(dst,src) for _,v in pairs(src) do dst[#dst+1] = v end end

-- records that are not contained in other records
local root_records={}
local record_type_groups={}
local clear_funcs={}
local global_scope={}
function clear_all_records()
	root_records={}
	record_type_groups={}
	-- run clear functions
	for i,func in ipairs(clear_funcs) do
		func()
	end
	global_scope={}
end
function reg_clear_func(func)
	clear_funcs[#clear_funcs + 1] = func
end

-- get a named record with rec_type
function get_named_record(rec_type, name)
	local recs = record_type_groups[rec_type]
	if recs ~= nil then
		return recs[name]
	end
end

local function group_add_record(rec, rec_type)
	-- add this record to the list of records with the same type.
	local type_group = record_type_groups[rec_type]
	if type_group == nil then
		type_group = {}
		record_type_groups[rec_type] = type_group
	end
	type_group[#type_group+1] = rec
	if name ~= nil then
		type_group[name] = rec
	end
end

local variable_format="%s_idx%d"
function set_variable_format(format)
	variable_format = format
end
function format_variable(name, idx)
	return variable_format:format(name, idx)
end

-- Meta-table used by all records.
local ignore_record={_rec_type = "ignore"}
local rec_meta
rec_meta={
clear = function(self)
	self._vars = {}
	self._data_parts = {}
	self._rec_counts = {}
end,
--
-- add data output functions to record.
--
-- replace variables in "part"
vars_part = function(self, part)
	local tmpl = self:dump_parts({part})
	tmpl = tmpl:gsub("%${(.-)}", self._vars)
	self._data_parts[part] = {tmpl}
	return tmpl
end,
-- replace variables in "parts"
vars_parts = function(self, parts)
	local out={}
	parts = self:parts(parts)
	-- apply variables to all "parts".
	for _,part in ipairs(parts) do
		local d = self:vars_part(part)
		out[#out+1] = d
	end
	return out
end,
-- append data to "part"
write_part = function(self, part, data)
	if type(data) ~= "table" then
		if data == nil then return end
		data = { tostring(data) }
	end
	local out=self._data_parts[part]
	if out == nil then
		out = {}
		self._data_parts[part] = out
	end
	-- append data.
	tappend(out, data)
end,
parts = function(self, parts)
	-- make sure "parts" is a table.
	if parts == nil then
		parts = {}
		for part in pairs(self._data_parts) do parts[#parts+1] = part end
	elseif type(parts) ~= "table" then
		parts = { parts }
	end
	return parts
end,
dump_parts = function(self, parts, sep)
	local out={}
	parts = self:parts(parts)
	-- return all parts listed in "parts".
	local data = self._data_parts
	for _,part in ipairs(parts) do
		local d_part=data[part]
		if d_part then
			tappend(out, d_part)
		end
		if sep ~= nil then
			out[#out+1] = sep
		end
	end
	return table.concat(out)
end,
-- copy parts from "src" record.
copy_parts = function(self, src, parts)
	parts = src:parts(parts)
	for _,part in ipairs(parts) do
		self:write_part(part, src:dump_parts(part))
	end
end,
--
-- functions for counting sub-records
--
get_sub_record_count = function(self, _rec_type)
	local count = self._rec_counts[_rec_type]
	if count == nil then count = 0 end
	return count
end,
count_sub_record = function(self, rec)
	local count = self:get_sub_record_count(rec._rec_type)
	count = count + 1
	self._rec_counts[rec._rec_type] = count
	rec._rec_idx = count
end,
--
-- functions for adding named variables
--
add_var = function(self, key, value)
	self._vars[key] = value
end,
add_rec_var = function(self, rec, name)
	local name = name or rec.name
	local idx = rec._rec_idx
	self._vars[name] = format_variable(name, idx)
	self._vars[name .. "::idx"] = idx
end,
--
-- sub-records management functions
--
make_sub_record = function(self, parent)
	local root_idx
	-- find record in roots list
	for idx,rec in ipairs(root_records) do
		if rec == self then
			root_idx = idx
			break
		end
	end
	-- remove it from the roots list
	if root_idx ~= nil and root_records[root_idx] == self then
		tremove(root_records, root_idx)
	end
	rawset(self, "_parent", parent)
end,
insert_record = function(self, rec, pos)
	rec:make_sub_record(self)
	if pos ~= nil then
		tinsert(self, pos, rec)
	else
		self[#self+1] = rec
	end
end,
add_record = function(self, rec)
	self:insert_record(rec)
end,
replace_record = function(self, old_rec, new_rec)
	for i=1,#self do
		local sub = self[i]
		if sub == old_rec then
			self[i] = new_rec
			return
		end
	end
end,
remove_record = function(self, rec)
	for i=1,#self do
		local sub = self[i]
		if sub == rec then
			rawset(self, i, ignore_record) -- have to insert an empty table in it's place.
			rawset(sub, "_parent", nil)
			return
		end
	end
end,
--
-- delete a record and all it's sub-records
--
delete_record = function(self)
	-- remove from parent.
	if self._parent ~= nil then
		self._parent:remove_record(self)
	end
	-- delete sub-records
	for i,sub in ipairs(self) do
		if is_record(sub) and sub._parent == self then
			self[i] = nil
			sub:delete_record()
			rawset(sub, "_parent", nil)
		end
	end
	-- ignore this record and it sub-records
	self._rec_type = "ignore"
end,
--
-- Copy record and all it's sub-records.
--
copy_record = function(self)
	local copy = {}
	-- copy values from current record.
	for k,v in pairs(self) do
		copy[k] = v
	end
	rawset(copy, "_parent", nil) -- unlink from old parent
	-- copy sub-records
	for i,sub in ipairs(copy) do
		if is_record(sub) then
			local sub_copy = sub:copy_record()
			rawset(copy, i, sub_copy)
			rawset(sub_copy, "_parent", copy)
		end
	end
	setmetatable(copy, rec_meta)
	group_add_record(copy, copy._rec_type)
	return copy
end,
--
-- Symbol resolver
--
add_symbol = function(self, name, obj, scope)
	-- default scope 'local'
	if scope == nil then scope = "local" end
	-- if scope is global then skip local maps.
	if scope == 'global' then
		global_scope[name] = obj
		return
	end
	-- add symbol to local map
	self._symbol_map[name] = obj
	-- if scope is doesn't equal our scope
	if scope ~= self.scope and self._parent ~= nil then
		self._parent:add_symbol(name, obj, scope)
	end
end,
get_symbol = function(self, name)
	-- check our mappings
	local obj = self._symbol_map[name]
	-- check parent if we don't have a mapping for the symbol
	if obj == nil and self._parent ~= nil then
		obj = self._parent:get_symbol(name)
	end
	-- next check the imports for the symbol
	if obj == nil then
		for _,import in ipairs(self._imports) do
			obj = import:get_symbol(name)
			if obj ~= nil then
				break
			end
		end
	end
	-- next check the globals for the symbol
	if obj == nil then
		obj = global_scope[name]
	end
	return obj
end,
-- import symbols from a "file" record
add_import = function(self, import_rec)
	local imports = self._imports
	-- if already imported then skip
	if imports[import_rec] then return end
	imports[import_rec] = true
	-- append to head of imports list so that the last import overrides symbols
	-- from the previous imports
	table.insert(imports, 1, import_rec)
end,
}
rec_meta.__index = rec_meta
function is_record(rec)
	-- use a metatable to identify records
	return (getmetatable(rec) == rec_meta and rec._rec_type ~= nil)
end
setmetatable(ignore_record, rec_meta)

local function remove_child_records_from_roots(rec, seen)
	-- make sure we don't get in a reference loop.
	if seen == nil then seen = {} end
	if seen[rec] then return end
	seen[rec] = true
	-- remove from root list.
	for _,val in ipairs(rec) do
		if is_record(val) then
			val:make_sub_record(rec)
		end
	end
end

local function end_record(rec)
	if type(rec) ~= 'function' then return rec end

	local rc, result = pcall(rec, nil)
	if not rc then
		print("Error processing new record: " .. result)
		return rec
	end
	return end_record(result)
end

function make_record(rec, rec_type, name, scope)
	if rec == nil then rec = {} end
	if type(rec) ~= "table" then rec = { rec } end
	-- set record's name.
	if name == nil then name = rec_type end
	rec.name = name
	-- record's symbol scope
	rec.scope = scope
	rec._symbol_map = {}
	rec._imports = {}

	-- make "rec" into a record.
	rec._rec_type = rec_type
	setmetatable(rec, rec_meta)

	-- complete partial child records.
	for i,val in ipairs(rec) do
		if type(val) == 'function' then
			val = end_record(val)
			rec[i] = val
		end
	end

	-- remove this record's child records from the root list.
	remove_child_records_from_roots(rec)

	-- add this record to the root list.
	root_records[#root_records + 1] = rec

	group_add_record(rec, rec_type)

	return rec
end

--
-- Record parser
--
local function record_parser(callbacks, name)
	name = name or "parse"
	local function call_meth(self, rec_type, post, rec, parent)
		local func = self[rec_type .. post]
		if func == nil then
			func = self["unknown" .. post]
			if func == nil then return end
		end
		return func(self, rec, parent)
	end
	local seen={}
	callbacks = setmetatable(callbacks, {
	__call = function(self, rec, parent)
		-- make sure it is a valid record.
		if not is_record(rec) or seen[rec] or rec._rec_type == "ignore" then return end
		if parent then
			parent:count_sub_record(rec) -- count sub-records.
		end
		-- keep track of records we have already processed
		seen[rec] = true
		local rec_type = rec._rec_type
		-- clear record's data output & sub-record counts.
		rec:clear()
		-- start record.
		call_meth(self, rec_type, "", rec, parent)
		-- transverse into sub-records
		for _,v in ipairs(rec) do
			self(v, rec)
		end
		-- end record
		call_meth(self, rec_type, "_end", rec, parent)
		-- update "last_type"
		self.last_type = rec_type
	end
	})
	return callbacks
end

function process_records(parser)
	record_parser(parser)
	-- process each root record
	for i,rec in ipairs(root_records) do
		parser(rec)
	end
	return parser
end

local stages = {}
function reg_stage_parser(stage, parser)
	local parsers = stages[stage]
	if parsers == nil then
		-- new stage add it to the end of the stage list.
		stages[#stages + 1] = stage
		parsers = {}
		stages[stage] = parsers
	end
	parsers[#parsers + 1] = parser
end

-- setup default stages
local default_stages = { "symbol_map", "imports" }

-- run all parser stages.
function run_stage_parsers()
	for _,stage in ipairs(stages) do
		local parsers = stages[stage]
		for _,parser in ipairs(parsers) do
			process_records(parser)
		end
	end
end

function move_recs(dst, src)
	-- move records from "rec" to it's parent
	for k,rec in ipairs(src) do
		if is_record(rec) and rec._rec_type ~= "ignore" then
			src:remove_record(rec) -- remove from src
			dst:add_record(rec) -- add to dst
		end
	end
	-- now delete this empty container record
	src:delete_record()
end

--
-- Record functions -- Used to create new records.
--
function make_generic_rec_func(rec_type, no_name)
	if _G[rec_type] ~= nil then error("global already exists with that name: " .. rec_type) end
	if not no_name then
		_G[rec_type] = function(name)
			return function(rec)
				rec = make_record(rec, rec_type, name)
				return rec
			end
		end
	else
		_G[rec_type] = function(rec)
			rec = make_record(rec, rec_type, rec_type)
			return rec
		end
	end
end

local path_char = package.config:sub(1,1)
local path_match = '(.*)' .. path_char
local path_stack = {''}
function subfile_path(filename)
	local level = #path_stack
	local cur_path = path_stack[level] or ''
	return cur_path .. filename
end
function subfiles(files)
	local level = #path_stack
	local cur_path = path_stack[level]
	level = level + 1
	-- use a new roots list to catch records from subfiles
	local prev_roots = root_records
	root_records={}

	-- process subfiles
	for _,file in ipairs(files) do
		-- add current path to file
		file = cur_path .. file
		-- seperate file's path from the filename.
		local file_path = file:match(path_match) or ''
		if #file_path > 0 then
			file_path = file_path .. path_char
		end
		-- push the file's path onto the path_stack only if it is different.
		if cur_path ~= file_path then
			path_stack[level] = file_path
		end
		-- check file path
		print("Parsing records from file: " .. file)
		dofile(file)
		-- pop path
		if cur_path ~= file_path then
			path_stack[level] = nil
		end
	end
	-- move sub-records into new array
	local rec={}
	for _,sub in ipairs(root_records) do
		rec[#rec + 1] = sub
	end

	-- switch back to previous roots list
	root_records = prev_roots

	-- make this into a record holding the sub-records from each of the sub-files
	rec = make_record(rec, "subfiles")
	return rec
end
-- process some container records
reg_stage_parser("containers", {
subfiles = function(self, rec, parent)
	move_recs(parent, rec)
end,
})

local subfolders={}
function subfolder(folder)
	return function(...)
	local files=select(1, ...)
	if type(files) ~= 'table' then
		files = {...}
	end
	-- push subfolder
	subfolders[#subfolders+1] = folder
	-- build full path
	folder = table.concat(subfolders, "/") .. "/"
	for i,file in ipairs(files) do
		files[i] = folder .. file
	end
	-- use subfile record.
	local rec = subfiles(files)
	-- pop subfolder
	subfolders[#subfolders] = nil
	return rec
end
end

function import(name)
	rec = make_record({}, "import", name)
	return rec
end
-- resolve imports
reg_stage_parser("imports", {
import = function(self, rec, parent)
end,
})

