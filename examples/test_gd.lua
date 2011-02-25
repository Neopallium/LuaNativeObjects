
local gd = require"gd"

local x = 200
local y = 200
local img = gd.gdImage(x,y)

local white = img:color_allocate(0xff, 0xff, 0xff)
local blue = img:color_allocate(0, 0, 0xff)
local red = img:color_allocate(0xff, 0, 0)

-- draw lines
for i=1,100000 do
	img:line(0, 0, y, x, blue)
	img:line(0, y, y, 0, red)
end

-- write image
img:toPNG('test.png')

