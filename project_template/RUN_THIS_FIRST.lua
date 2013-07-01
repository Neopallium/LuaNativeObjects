print[[
This script will help setup a new bindings project for you.
]]

local stat, lfs = pcall(require, "lfs")
if not stat then
	print("Failed to load LuaFileSystem: " .. tostring(lfs))
	os.exit()
end

-- get directory separator
local dir_sep = package.config:sub(1,1)

-- get current directory
local template_dir = lfs.currentdir() .. dir_sep
local attr = lfs.attributes(template_dir .. '__mod_name__.nobj.lua')
if not attr then
	print("Can't find project template files, please run script in the template's folder.")
	os.exit()
end

print("Enter the module name (i.e. gd, png, event):")
local mod_name = string.lower(io.read"*l")
local MOD_NAME = string.upper(mod_name)
local Mod_name = MOD_NAME:sub(1,1) .. mod_name:sub(2)

print("Enter the Author's name (i.e. your name):")
local authors_name = string.lower(io.read"*l")

print("Enter the folder where you want to create the new project:")
local project_path = string.lower(io.read"*l") or "."
if #project_path == 0 then project_path = "." end
-- expand '~' prefix to HOME
if project_path:sub(1,1) == '~' then
	local home = os.getenv("HOME")
	project_path = home .. project_path:sub(2)
end
-- check if path exists
local attr = lfs.attributes(project_path)
if attr then
	-- path exists, install project in project_path/lua-mod_name
	project_path = project_path .. dir_sep .. 'lua-' .. mod_name
end

print("\n\nPlease verify this info:")
print(string.format('Module name: "%s"', mod_name))
print(string.format('Author\'s name: "%s"', authors_name))
print(string.format('Project path: "%s"', project_path))
print("Press Enter to setup project (or Ctrl-C to cancel):")
io.read"*l"

--
-- helper functions
--
local function copyfile(src, dst, filter)
	local content
	--
	-- read source file
	--
	local file = assert(io.open(src, "r"))
	content = file:read("*a")
	file:close()
	--
	-- Apply content filter
	--
	if filter then
		content = filter(content)
	end
	--
	-- write content to destination file
	--
	local file = assert(io.open(dst, "w"))
	file:write(content)
	file:close()
end

local template_replacements = {
["__mod_name__"] = mod_name,
["__MOD_NAME__"] = MOD_NAME,
["__Mod_name__"] = Mod_name,
["__authors_name__"] = authors_name,
}
local function template_filter(content)
	return content:gsub("(__[%w]*_[%w]*__)", template_replacements)
end

--
-- Install project
--
local sub_dirs = {
	"cmake",
	"src",
}
local copy_files = {
	"cmake/LuaNativeObjects.cmake",
	"src/object.nobj.lua",
	"README.regenerate.md",
}
local template_files = {
	"CMakeLists.txt",
	"__mod_name__.nobj.lua",
	"lua-__mod_name__-scm-0.rockspec",
	-- rename this file
	["PROJECT_README.md"] = "README.md",
}

-- create directories
assert(lfs.mkdir(project_path))
project_path = project_path .. dir_sep
for i=1,#sub_dirs do
	assert(lfs.mkdir(project_path .. sub_dirs[i]))
end

-- copy files
for i=1,#copy_files do
	local file = copy_files[i]
	copyfile(template_dir .. file, project_path .. file)
end

-- copy template files
for src,dst in pairs(template_files) do
	if type(src) == 'number' then
		-- src & dst are the same name
		src = template_dir .. dst
	else
		-- src name is different dst name
		src = template_dir .. src
	end
	-- apply template replacements to dst name
	dst = project_path .. template_filter(dst)
	-- apply template replacements to src files content and copy to destination.
	copyfile(src, dst, template_filter)
end

