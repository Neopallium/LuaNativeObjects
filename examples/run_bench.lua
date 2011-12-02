
local bench = require"bench"
local zmq = require"zmq"

local N = tonumber(arg[1] or 1000000)

local test = bench.method_call()

local timer = zmq.stopwatch_start()

for i=1,N do
	test:simple()
end

local elapsed = timer:stop()
if elapsed == 0 then elapsed = 1 end

local throughput = N / (elapsed / 1000000)

print(string.format("finished in %i sec, %i millisec and %i microsec, %i calls/s",
(elapsed / 1000000), (elapsed / 1000) % 1000, (elapsed % 1000), throughput
))


