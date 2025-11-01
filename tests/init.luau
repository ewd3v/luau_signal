local Signal = require("./src/signal")
assert(type(Signal) == "table", "Library does not return a table")

assert(Signal.new(), ".new() does not create a signal")
assert(Signal.is(Signal.new()), ".is() does not return true for Signal objects")
assert(not Signal.is("test"), ".is() does not return false for non-Signal objects")

local function getTracker()
	local tracker = {
		calls = {},
	}

	function tracker.clear()
		table.clear(tracker.calls)
	end

	return tracker, function(...)
		table.insert(tracker.calls, table.pack(...))
	end
end

do
	local signal = Signal.new()
	local tracker, func = getTracker()
	local connection = assert(signal:Connect(func), "Signal:Connect doesnt return a connection")

	signal:Fire(1, 2, 3)
	assert(#tracker.calls == 1, "Signal doesn't fire connections")
	signal:Fire(4, 5, 6, "str")
	assert(#tracker.calls == 2, "Signal doesn't fire connections twice")

	assert(tracker.calls[1].n == 3, "bad arg count")
	assert(tracker.calls[1][1] == 1, "incorrect arg")
	assert(tracker.calls[1][2] == 2, "incorrect arg")
	assert(tracker.calls[1][3] == 3, "incorrect arg")

	assert(tracker.calls[2].n == 4, "bad arg count")
	assert(tracker.calls[2][1] == 4, "incorrect arg")
	assert(tracker.calls[2][2] == 5, "incorrect arg")
	assert(tracker.calls[2][3] == 6, "incorrect arg")
	assert(tracker.calls[2][4] == "str", "incorrect arg")

	tracker.clear()

	connection:Disconnect()
	signal:Fire()
	assert(connection.Connected == false, ":Disconnect() doesn't disconnect")
	assert(#tracker.calls == 0, "Signals fire disconnected connections")

	connection:Reconnect()
	signal:Fire()
	assert(connection.Connected :: any == true, ":Disconnect() doesn't reconnect")
	assert(#tracker.calls == 1, "Signals doesn't fire reconnected connections")

	signal:DisconnectAll()
	signal:Fire()
	assert(connection.Connected == false, ":DisconnectAll() doesn't disconnect")
	assert(#tracker.calls == 1, "Signals fire connections disconnected via :DisconnectAll")

	tracker.clear()
end

assert(
	Signal.isConnection(Signal.new():Connect(function() end)),
	".isConnection() does not return true for Connection objects"
)
assert(not Signal.isConnection("test"), ".isConnection() does not return false for non-Connection objects")

do
	local signal = Signal.new()
	local order = {}

	signal:Connect(function()
		table.insert(order, 1)
	end)
	signal:Connect(function()
		table.insert(order, 2)
	end)

	signal:Fire()
	assert(order[1] == 2 and order[2] == 1, "incorrect firing order")
end

do
	local signal = Signal.new()
	local tracker, func = getTracker()
	local connection = signal:Once(func)
	signal:Fire()
	assert(#tracker.calls == 1, ":Once doesn't connect")
	assert(connection.Connected == false, ":Once doesnt disconnect after firing")
	signal:Fire()
	assert(#tracker.calls == 1, ":Once allows multiple fires")

	connection:Reconnect()
	signal:Fire()
	assert(#tracker.calls == 2, ":Reconnect doesn't work with :Once")
	signal:Fire()
	assert(#tracker.calls == 2, ":Reconnect allows :Once to fire multiple times")
end

do
	local signal = Signal.new()
	local reached = false
	local thread = coroutine.create(function()
		assert(signal:Wait() == "test", ":Wait does not return the correct arguments")
		reached = true
	end)
	coroutine.resume(thread)

	assert(reached == false, ":Wait does not yield")
	signal:Fire("test")
	assert(reached :: any == true, ":Wait does not resume")
end

do
	local signal = Signal.new()
	local reached = false
	signal:Once(function()
		signal:Connect(function()
			reached = true
		end)
	end)

	signal:Fire()
	assert(reached == false, "Connections getting connected mid-fire shouldnt fire")
	signal:Fire()
	assert(reached :: any == true, "Connections getting connected mid-fire should fire the next :Fire")
end

do
	local signal = Signal.new()
	local connection
	connection = signal:Connect(function()
		connection:Disconnect()
	end)

	signal:Fire()
	assert(
		connection.Connected == false,
		"Connections should be able to disconnect themselves from inside it's callback"
	)
end
