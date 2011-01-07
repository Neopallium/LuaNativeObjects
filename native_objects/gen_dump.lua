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
-- dump records
--
print"============ Dump records ================="
local depth=0
function write(...)
	io.write(("  "):rep(depth))
	io.write(...)
end

process_records{
unknown = function(self, rec, parent)
	write(rec._rec_type .. " {\n")
	depth = depth + 1
	-- dump rec info
	for k,v in pairs(rec) do
		if k == '_rec_type' then
		elseif k == 'c_type_rec' then
			write(k,' = ', tostring(v._rec_type), ' = {\n')
			depth = depth + 1
			write('name = "', tostring(v.name), '"\n')
			write('c_type = "', tostring(v.c_type), '"\n')
			write('lang_type = "', tostring(v.lang_type), '"\n')
			depth = depth - 1
			write('}\n')
		elseif is_record(v) then
		elseif type(v) == 'function' then
		elseif type(v) == 'table' then
		else
			write(tostring(k),' = "', tostring(v), '"\n')
		end
	end
end,
unknown_end = function(self, rec, parent)
	depth = depth - 1
	write("}\n")
end,
c_source = function(self, rec, parent)
	local src = rec.src
	if type(src) == 'table' then src = table.concat(src) end
	write('c_source = "', src, '"\n')
end,
c_source_end = function(self, rec, parent)
end,
}

