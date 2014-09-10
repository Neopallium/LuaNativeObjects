print(package.cpath)
local path_sep = package.config:sub(3,3)
print('path_sep = ', path_sep)

local path_match = "([^" .. path_sep .. "]+)"
print('match = ', path_match)
for path in package.cpath:gmatch(path_match) do
	print(path)
end

