--[=[
	@class Connection

	A class representing a function connected to a [Signal].
]=]
local Connection = {} :: connectionImpl
Connection.__index = Connection

export type Connection = typeof(setmetatable({} :: connection, Connection))
type connection = {
	Connected: boolean,

	-- Types changed to any was done because the typechecker did not like cyclic types
	-- They are private anyways

	_signal: any, -- Signal<T...>,
	_callback: (...any) -> (),
	_next: Connection?,
	_prev: Connection?,

	_destroyed: boolean?,
}
type connectionImpl = {
	__index: connectionImpl,

	Disconnect: (self: Connection) -> (),
	Reconnect: (self: Connection) -> (),
	Destroy: (self: Connection) -> (),
}

--[=[
	Wether this connection is currently connected or not.

	@within Connection
	@prop Connected boolean
	@readonly
]=]

--[=[
	A reference to this connections signal.

	@within Connection
	@prop _signal Signal<T...>
	@private
]=]

--[=[
	The callback connected to this connection.

	@within Connection
	@prop _callback (T...) -> ()
	@private
]=]

--[=[
	A reference to the connection that should be fired after this one

	@within Connection
	@prop _next Connection<...any>
	@private
]=]

--[=[
	A reference to the connection that should be fired before this one

	@within Connection
	@prop _prev Connection<...any>
	@private
]=]

--[=[
	If present, indicates that this object is destroyed.

	@within Connection
	@prop _destroyed true?
	@private
	@readonly
]=]

--[=[
	Disconnects this connection.
]=]
function Connection:Disconnect()
	if self._destroyed == true then
		error("Cannot :Disconnect(), Connection is destroyed", 2)
	end

	if not self.Connected then
		return
	end
	self.Connected = false

	local signal = self._signal
	local next = self._next
	local prev = self._prev

	if next ~= nil then
		next._prev = prev
	end

	if prev ~= nil then
		prev._next = next
	end

	if signal._head == self then
		signal._head = next
	end
end

--[=[
	Reconnects this connection.
]=]
function Connection:Reconnect()
	if self._destroyed == true then
		error("Cannot :Reconnect(), Connection is destroyed", 2)
	end

	if self.Connected then
		return
	end
	self.Connected = true

	local signal = self._signal
	local head = signal.head

	signal._head = self
	if head ~= nil then
		head._prev = self
	end

	self._next = head
	self._prev = nil
end

--[=[
	Calls [Connections:Disconnect] and destroys this connection, preventing reconnecting this event.
]=]
function Connection:Destroy()
	if self._destroyed == true then
		return
	end

	self:Disconnect()
	self._destroyed = true
	table.freeze(self)
end

--[=[
	@class Signal

	A class holding a list of [Connections](Connection) and methods to fire and connect them.
]=]
local Signal = {} :: signalImpl
Signal.__index = Signal

export type Signal<T...> = typeof(setmetatable({} :: signal<T...>, Signal))
type signal<T...> = {
	_head: Connection?,

	_destroyed: true?,
}
type signalImpl = {
	__index: signalImpl,

	is: (value: Signal<...any> | any) -> boolean,
	isConnection: (value: Connection | any) -> boolean,
	new: <T...>() -> Signal<T...>,

	Connect: <T...>(self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Once: <T...>(self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Wait: <T...>(self: Signal<T...>) -> T...,

	Fire: <T...>(self: Signal<T...>, T...) -> (),

	DisconnectAll: (self: Signal<...any>) -> (),
	Destroy: (self: Signal<...any>) -> (),
}

--[=[
	A reference to the connection that should be fired first.

	@within Signal
	@prop _head Connection<...any>?
	@private
]=]

--[=[
	If present, indicates that this object is destroyed.

	@within Signal
	@prop _destroyed true?
	@private
	@readonly
]=]

--[=[
	Returns true if the given value is a [Signal].
]=]
function Signal.is(value: Signal<...any> | any): boolean
	return type(value) == "table" and getmetatable(value) == Signal
end

--[=[
	Returns true if the given value is a [Connection].
]=]
function Signal.isConnection(value: Connection | any): boolean
	return type(value) == "table" and getmetatable(value) == Connection
end

--[=[
	Creates a new [Signal].
]=]
function Signal.new<T...>(): Signal<T...>
	return setmetatable({
		_head = nil,
	}, Signal)
end

--[=[
	Creates a new [Connection] with the provided callback.
]=]
function Signal:Connect<T...>(callback: (T...) -> ()): Connection
	if self._destroyed == true then
		error("Cannot :Connect(), Signal is destroyed", 2)
	end

	local head = self._head
	local connection = setmetatable({
		Connected = true,

		_signal = self,
		_callback = callback,
		_next = head,
		_prev = nil,
	}, Connection)

	self._head = connection
	if head then
		head._prev = connection
	end

	return connection
end

--[=[
	Creates a new [Connection] with the provided callback that disconnects after getting fired.
]=]
function Signal:Once<T...>(callback: (T...) -> ()): Connection
	if self._destroyed == true then
		error("Cannot :Once(), Signal is destroyed", 2)
	end

	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)

	return connection
end

--[=[
	Yields the current thread and then resumes it when the signal gets fired.
	Returns the values the signal got fired with.
]=]
function Signal:Wait<T...>(): T...
	if self._destroyed == true then
		error("Cannot :Wait(), Signal is destroyed", 2)
	end

	local thread = coroutine.running()
	local connection
	connection = self:Connect(function(...)
		connection:Destroy()

		if coroutine.status(thread) == "suspended" then
			coroutine.resume(thread, ...)
		end
	end)

	return coroutine.yield()
end

local freeThread: thread?
local function runCallback(callback, ...)
	local acquiredThread = freeThread
	freeThread = nil
	callback(...)
	freeThread = acquiredThread
end

local function threadLoop()
	while true do
		runCallback(coroutine.yield())
	end
end

local spawn: (thread, ...any) -> () = if _G.RUNTIME == "lune"
	then require("@lune/task").spawn
	elseif _G.RUNTIME == "roblox" then task.spawn
	else function(thread, ...)
		local success, message = coroutine.resume(thread, ...)
		if not success then
			(warn or print)(debug.traceback(message, 3))
		end
	end

--[=[
	Fires all connections connected to this signal, and passes through the supplied to them arguments.
	The connections will get fired in the reverse order that they were connected in.
]=]
function Signal:Fire<T...>(...: T...)
	if self._destroyed == true then
		error("Cannot :Fire(), Signal is destroyed", 2)
	end

	local connection = self._head
	while connection ~= nil do
		if not freeThread then
			freeThread = coroutine.create(threadLoop)
			coroutine.resume(freeThread :: any) -- Get it into the loop
		end

		spawn(freeThread :: any, connection._callback, ...)
		connection = connection._next
	end
end

--[=[
	Disconnects all connections currently connected to this signal.
]=]
function Signal:DisconnectAll()
	if self._destroyed == true then
		error("Cannot :DisconnectAll(), Signal is destroyed", 2)
	end

	local connection = self._head
	while connection do
		connection:Disconnect()
		connection = connection._next
	end
end

--[=[
	Calls [Signal:DisconnectAll] and destroys this signal, preventing connecting any new signals.
]=]
function Signal:Destroy()
	if self._destroyed == true then
		return
	end

	self:DisconnectAll()
	self._destroyed = true
	table.freeze(self)
end

return Signal
