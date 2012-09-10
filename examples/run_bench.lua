
local bench = require"bench"
local zmq = require"zmq"

local N = tonumber(arg[1] or 10000000)

local function run_bench(action_name, N, func)

	local timer = zmq.stopwatch_start()
	
	func()
	
	local elapsed = timer:stop()
	if elapsed == 0 then elapsed = 1 end
	
	local throughput = N / (elapsed / 1000000)
	
	print(string.format("finished in %i sec, %i millisec and %i microsec, %i '%s'/s",
	(elapsed / 1000000), (elapsed / 1000) % 1000, (elapsed % 1000), throughput, action_name
	))
end

--
-- Run benchmarks of method calls.
--

local test = bench.method_call()

run_bench('C API method calls', N, function()
	for i=1,N do
		test:simple()
	end
end)

run_bench('null method calls', N, function()
	for i=1,N do
		test:null()
	end
end)


--
-- Run benchmarks of C callbacks.
--

local function callback(idx)
	return 0
end
local test = bench.TestObj(callback)

run_bench('wrapped state C callback', N, function()
	test:run(N)
end)

--
-- Run benchmarks of no wrap state C callbacks.
--

local function callback(idx)
	return 0
end
local test = bench.NoWrapTestObj()
test:register(callback)

run_bench('no wrap state C callback', N, function()
	test:run(N)
end)

