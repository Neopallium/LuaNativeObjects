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

-- Immutable Buffer interface
interface "Buffer" {
	interface_method "const uint8_t *" "const_data" {},
	interface_method "size_t" "get_size" {},
}
-- Mutable Buffer interface
interface "MutableBuffer" {
	interface_method "uint8_t *" "data" {},
	interface_method "size_t" "get_size" {},
}

-- object type for file descriptors
interface "FD" {
	interface_method "int" "get_fd" {},
	-- 0 = file, 1 = socket, -1 = other/unknown
	interface_method "int" "get_type" {},
}


--
--
-- Stage parser to handle interface records.
--
--

local tconcat = table.concat

reg_stage_parser("containers",{
interface = function(self, rec, parent)
	rec:add_var("interface_name", rec.name)
	-- check if the interface was defined outside any other record.
	if not parent then
		rec.is_global = true
	end
	rec.methods = {}
	rec.method_idx = 0

	rec:write_part("interface", {
		"typedef struct ${interface_name}_if {\n",
	})
end,
interface_end = function(self, rec, parent)
	local parts = { "interface", "defines"}
	rec:write_part("interface", {
		"} ${interface_name}IF;\n",
	})
	rec:write_part("defines",
		[[

/* a per-module unique pointer for fast lookup of an interface's implementation table. */
static char obj_interface_${interface_name}IF[] = "${interface_name}IF";

#define ${interface_name}IF_VAR(var_name) \
	${interface_name}IF *var_name ## _if; \
	void *var_name;

#define ${interface_name}IF_LUA_OPTIONAL(L, _index, var_name) \
	var_name = obj_implement_luaoptional(L, _index, (void **)&(var_name ## _if), \
		obj_interface_${interface_name}IF)

#define ${interface_name}IF_LUA_CHECK(L, _index, var_name) \
	var_name = obj_implement_luacheck(L, _index, (void **)&(var_name ## _if), \
		obj_interface_${interface_name}IF)

]])

	rec:write_part("ffi_obj_type", { [[
local obj_type_${interface_name}_check =
	obj_get_interface_check("${interface_name}IF", "Expected object with ${interface_name} interface")
]]})

	rec:vars_parts(parts)
	rec:add_record(c_source("typedefs")(
		rec:dump_parts(parts)
	))
	--
	-- FFI code
	--
	rec:add_record(ffi_source("ffi_pre_cdef")({
		'ffi_safe_cdef("', rec.name, 'IF", [[\n',
		rec:dump_parts("interface"),
		']])\n',
	}))
	local ffi_parts = { "ffi_obj_type" }
	rec:vars_parts(ffi_parts)
	for i=1,#ffi_parts do
		local part = ffi_parts[i]
		rec:add_record(ffi_source(part)(
			rec:dump_parts(part)
		))
	end
end,
interface_method = function(self, rec, parent)
	assert(parent.is_interface, "Can't have interface_method record in a non-interface parent.")
	assert(not parent.methods[rec.name], "Duplicate interface method.")
	parent.methods[rec.name] = rec
	-- record order of interface methods.
	local idx = parent.method_idx + 1
	parent.method_idx = idx
	rec.idx = idx
	local psrc = { "(void *this_v" }
  -- method parameters
  local params = rec.params
	local names = { }
  for i=1,#params,2 do
    local c_type = params[i]
    local name = params[i + 1]
		psrc[#psrc + 1] = ", "
		psrc[#psrc + 1] = c_type
		psrc[#psrc + 1] = " "
		psrc[#psrc + 1] = name
		names[#names + 1] = name
  end
	psrc[#psrc + 1] = ")"
	psrc = tconcat(psrc)
	if #names > 0 then
		names = ", " .. tconcat(names, ", ")
	else
		names = ""
	end
	-- add method to interface structure.
	parent:write_part("interface", {
		"  ", rec.ret, " (* const ", rec.name, ")", psrc, ";\n"
	})
	-- create function decl for method.
	rec.func_name = "${object_name}_${interface_name}_" .. rec.name
	rec.func_decl = rec.ret .. " " .. rec.func_name .. psrc
	rec.param_names = names
end,
implements = function(self, rec, parent)
	local interface = rec.interface_rec
	rec:add_var("interface_name", rec.name)
	rec.c_type = parent.c_type
	rec.if_methods = interface.methods
	rec.methods = {}

	rec:write_part("src", [[
/**
 * ${object_name} implements ${interface_name} interface
 */
]])
	rec:write_part("ffi_src", [[
-- ${object_name} implements ${interface_name} interface
do
  local impl_meths = obj_register_interface("${interface_name}IF", "${object_name}")
]])
end,
implements_end = function(self, rec, parent)
	local interface = rec.interface_rec
	local max_idx = interface.method_idx
	local define = {
		"\nstatic const ${interface_name}IF ${object_name}_${interface_name} = {\n",
	}
	local methods = rec.methods
	for idx=1,max_idx do
		local meth = methods[idx]
		if idx == 1 then
			define[#define + 1] = "  "
		else
			define[#define + 1] = ",\n  "
		end
		if meth then
			define[#define + 1] = "${object_name}_${interface_name}_" .. meth.name
		else
			define[#define + 1] = "NULL"
		end
	end
	define[#define + 1] = "\n};\n"

	rec:write_part("src", define)

	rec:write_part("ffi_src", {
	'end\n',
	})
	rec:write_part("regs", [[
  { "${interface_name}IF", &(${object_name}_${interface_name}) },
]])

	local parts = { "src", "ffi_src", "regs" }
	rec:vars_parts(parts)
	parent:add_record(c_source("implements")(
		rec:dump_parts("src")
	))
	parent:add_record(c_source("implement_regs")(
		rec:dump_parts("regs")
	))
	parent:add_record(ffi_source("ffi_src")(
		rec:dump_parts("ffi_src")
	))
end,
implement_method = function(self, rec, parent)
	local name = rec.name
	rec:add_var("this", "this_p")
	assert(parent.is_implements, "Can't have implement_method record in a non-implements parent.")
	local if_method = parent.if_methods[name]
	assert(if_method, "Interface doesn't contain this method.")
	local if_idx = if_method.idx
	assert(not parent.methods[if_idx], "Duplicate implement method.")
	parent.methods[if_idx] = rec
	-- generate code for method
	rec:write_part("src", {
		"/** \n",
		" * ${interface_name} interface method ", rec.name, "\n",
		" */\n",
		"static ", if_method.func_decl, " {\n",
		"  ", parent.c_type, " ${this} = this_v;\n",
	})
	if not rec.c_function then
		rec:write_part("ffi_src", {
			"-- ${interface_name} interface method ", rec.name, "\n",
			"function impl_meths.", rec.name, "(${this}", if_method.param_names, ")\n",
		})
		if rec.get_field then
			-- generate code to return a field from ${this}
			rec:write_part("src", {
				"  return ${this}->", rec.get_field, ";\n",
			})
			rec:write_part("ffi_src", {
				"  return ${this}.", rec.get_field, "\n",
			})
		end
	else
		-- wrap a C function that has the same parameters and return type.
		rec:write_part("src", {
			"  return ", rec.c_function, "(${this}", if_method.param_names, ");\n",
		})
		rec:write_part("ffi_src", {
			"-- ${interface_name} interface method ", rec.name, "\n",
			"impl_meths.", rec.name, " = C.", rec.c_function, "\n",
		})
	end
end,
implement_method_end = function(self, rec, parent)
	rec:write_part("src", {
		"}\n",
	})
	if not rec.c_function then
		rec:write_part("ffi_src", {
			"end\n",
		})
	end
	local parts = { "src", "ffi_src" }
	rec:vars_parts(parts)
	parent:copy_parts(rec, parts)
end,
c_source = function(self, rec, parent)
	parent:write_part(rec.part, rec.src)
end,
ffi_source = function(self, rec, parent)
	parent:write_part(rec.part, rec.src)
end,
})

