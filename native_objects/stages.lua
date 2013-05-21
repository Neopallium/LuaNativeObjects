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

local tconcat=table.concat
local assert=assert
local error=error
local type=type
local io=io
local pairs=pairs

--
-- process some container records
--
reg_stage_parser("containers",{
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
error_code = function(self, rec, parent)
	new_c_type(rec.name, rec)
end,
unknown = function(self, rec, parent)
	-- re-map c_types
	if rec._is_c_type ~= nil then
		new_c_type(rec.c_type, rec)
	end
end,
})

-- register place-holder
reg_stage_parser("resolve_types")

--
-- convert fields into get/set methods.
--
reg_stage_parser("fields",{
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
})

--
-- add 'this' variable to method records.
--
reg_stage_parser("this_variable",{
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
})

--
-- create callback_func & callback_state records.
--
reg_stage_parser("callback",{
var_in = function(self, rec, parent)
	-- is variable a callback type?
	if not rec.is_callback then return end
	-- get grand-parent container
	local container = parent._parent
	-- create callback_state instance.
	local cb_state
	if rec.owner == 'this' then
		local wrap_type = container.c_type
		cb_state = callback_state(wrap_type, rec.wrap_state)
		-- wrap 'this' object.
		container.callback_state = cb_state
		parent.callback_state = cb_state
		parent.state_owner = rec.owner
		if rec.state_var ~= 'this' then
			local state_var = tmp_var{ "void *", rec.state_var }
			parent.state_var = state_var
			parent:insert_record(state_var, 1)
		end
	else
		assert("un-supported callback owner type: " .. rec.owner)
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
})

--
-- process extends/dyn_caster records
--
reg_stage_parser("dyn_caster",{
_obj_cnt = 0,
object = function(self, rec, parent)
	rec._obj_id = self._obj_cnt
	self._obj_cnt = self._obj_cnt + 1
end,
import_object = function(self, rec, parent)
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
})

--
-- Create FFI-wrappers for inline/macro calls
--
local ffi_wrappers = {}
reg_stage_parser("ffi_wrappers",{
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
		"LUA_NOBJ_API ", cdef, " {\n",
		call,
		"}\n",
		}))
	end
	object:add_record(ffi_export_function(ret_type)(export_prefix .. rec.cfunc)(params))
end,
})

--
-- do some pre-processing of records.
--
local ffi_cdefs = {}
reg_stage_parser("pre-process",{
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
	if rec._is_method and parent.callback_state then
		if rec.is_destructor then
			rec.callback_state = parent.callback_state
		end
	end
	-- map names to in/out variables
	rec.var_map = {}
	function rec:add_variable(var, name)
		name = name or var.name
		local old_var = self.var_map[name]
		if old_var and old_var ~= var then
			-- allow input variable to share name with an output variable.
			assert(var.ctype == old_var.ctype,
					"duplicate variable " .. name .. " in " .. self.name)
			-- If they are the same type.
			local v_in,v_out
			if var._rec_type == 'var_in' then
				assert(old_var._rec_type == 'var_out',
					"duplicate input variable " .. name .. " in " .. self.name)
				v_in = var
				v_out = old_var
			elseif var._rec_type == 'var_out' then
				assert(old_var._rec_type == 'var_in',
					"duplicate output variable " .. name .. " in " .. self.name)
				v_in = old_var
				v_out = var
			end
			-- link in & out variables.
			v_in.has_out = v_out
			v_out.has_in = v_in
			-- store input variable in var_map
			var = v_in
		end
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
	local idx=1
	for i=1,#params,2 do
		local c_type = params[i]
		local name = params[i + 1]
		if i > 1 then
			src[#src+1] = ", "
			typedef[#typedef+1] = ", "
		end
		-- add cb_in to this rec.
		local v_in = cb_in{ c_type, name}
		rec:insert_record(v_in, idx)
		idx = idx + 1
		src[#src+1] = c_type .. " ${" .. v_in.name .. "}"
		typedef[#typedef+1] = c_type .. " " .. v_in.name
		vars[#vars+1] = "${" .. v_in.name .. "}"
	end
	src[#src+1] = ")"
	typedef[#typedef+1] = ");"
	-- save callback func decl.
	rec.c_func_decl = tconcat(src)
	rec.c_func_typedef = tconcat(typedef)
	rec.param_vars = tconcat(vars, ', ')
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
	if not rec.is_length_ref then
		parent:add_variable(rec)
	end
end,
cb_in = function(self, rec, parent)
	parent:add_variable(rec)
end,
cb_out = function(self, rec, parent)
	if not rec.is_length_ref then
		parent:add_variable(rec)
	end
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
				rc = var_out{ ret, "rc_" .. rec.cfunc, is_unnamed = true }
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
			end
			-- add var_out record to parent
			parent:add_record(rc)
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
		ffi_src[#ffi_src+1] = "Cmod." .. rec.ffi_export_prefix
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
			-- variable exists, turn this input variable into a reference.
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
	local idx = parent:find_record(rec)
	idx = idx + 1
	parent:insert_record(c_source("src")(src), idx)
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
	idx = idx + 1
	parent:insert_record(ffi_source("ffi_src")(ffi_src), idx)
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
})

--
-- sort var_in/var_out records.
--
local function sort_vars(var1, var2)
	return (var1.idx < var2.idx)
end
reg_stage_parser("variables",{
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
})

-- register place-holder
reg_stage_parser("lang_type_process")

--
-- mark functions which have an error_code var_out.
--
reg_stage_parser("error_code",{
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
})

-- register place-holder
reg_stage_parser("pre_gen")

