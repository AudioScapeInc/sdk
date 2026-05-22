--!strict
-- Roblox-shaped globals (`game`, `workspace`, `Instance`) for Lune-based
-- unit tests. Only models the surface the SDK actually touches at module
-- load + during the methods we test.

local taskLib = require("@lune/task")

export type Services = {
	HttpService: any?,
	RunService: any?,
	Players: any?,
	ReplicatedStorage: any?,
	SoundService: any?,
}

local function noopConnection()
	return { Disconnect = function() end }
end

local function makeRunService()
	return {
		IsServer = function()
			return true
		end,
		IsClient = function()
			return false
		end,
		IsStudio = function()
			return false
		end,
		-- Defaults to false so the analytics loop doesn't auto-start during
		-- unit tests; specs that want to exercise the loop should override
		-- this in opts.services.
		IsRunning = function()
			return false
		end,
		Heartbeat = {
			Connect = function(_, _fn: any)
				return noopConnection()
			end,
		},
	}
end

local function makePlayers()
	return {
		PlayerRemoving = {
			Connect = function(_, _fn: any)
				return noopConnection()
			end,
		},
		GetPlayers = function()
			return {}
		end,
	}
end

local function makeReplicatedStorage()
	return setmetatable({}, {
		__index = function(_, k)
			error("ReplicatedStorage." .. tostring(k) .. " not implemented in mockGame", 2)
		end,
	})
end

local function makeWorkspace()
	return {
		-- Roblox's `workspace:GetServerTimeNow()` returns Unix time as a float
		-- with sub-second precision. Several SDK paths (analytics enqueue
		-- timestamp in particular) compare against now, so returning
		-- `os.clock()` (seconds-since-process-start) makes events look like
		-- they're from 1970 — the analytics API rejects timestamps older
		-- than 7 days.
		GetServerTimeNow = function(_)
			return os.time() + (os.clock() % 1)
		end,
	}
end

-- A minimal Instance shim. Stores arbitrary properties and provides the small
-- set of methods/signals the SDK touches at runtime: Play/Stop/Destroy on
-- audio instances, and an Ended signal on AudioPlayer. Created instances are
-- recorded on `Instance.__created` so tests can find them by ClassName without
-- having to walk a parent's children (the shim doesn't model children).
local function makeInstance()
	local created: { any } = {}
	local InstanceTable: { [string]: any } = {}
	InstanceTable.__created = created

	local function makeSignal()
		local handlers: { (...any) -> () } = {}
		local signal: { [string]: any } = {}
		signal.Connect = function(_, fn: (...any) -> ())
			table.insert(handlers, fn)
			return {
				Disconnect = function()
					for i, h in ipairs(handlers) do
						if h == fn then
							table.remove(handlers, i)
							break
						end
					end
				end,
			}
		end
		-- Test-only fire hook
		signal._fire = function(...)
			for _, h in ipairs(handlers) do
				h(...)
			end
		end
		return signal
	end

	InstanceTable.new = function(className: string)
		local props: { [string]: any } = {
			ClassName = className,
			Ended = makeSignal(),
		}
		local inst
		inst = setmetatable(props, {
			__index = function(_, k)
				return rawget(props, k)
			end,
			__newindex = function(_, k, v)
				rawset(props, k, v)
			end,
		})
		props.Play = function() end
		props.Stop = function() end
		props.Destroy = function()
			(props :: any)._destroyed = true
		end
		table.insert(created, inst)
		return inst
	end

	return InstanceTable
end

local function makeTask()
	-- Lune's @lune/task is API-compatible with Roblox's task library for the
	-- bits the SDK uses (wait, defer, spawn, delay).
	return {
		wait = taskLib.wait,
		defer = taskLib.defer,
		spawn = taskLib.spawn,
		delay = taskLib.delay,
		cancel = taskLib.cancel,
	}
end

local function makeGame(services: Services, opts: { gameId: number?, placeId: number? }?)
	opts = opts or {}
	local resolved: { [string]: any } = {
		HttpService = services.HttpService,
		RunService = services.RunService or makeRunService(),
		Players = services.Players or makePlayers(),
		ReplicatedStorage = services.ReplicatedStorage or makeReplicatedStorage(),
		SoundService = services.SoundService or {},
	}
	return {
		GetService = function(_, name: string)
			local svc = resolved[name]
			if svc == nil then
				error("mockGame: unknown service " .. name, 2)
			end
			return svc
		end,
		BindToClose = function(_, _fn: any)
			-- no-op; integration tests can override if they care about shutdown order
		end,
		GameId = (opts :: any).gameId or 0,
		PlaceId = (opts :: any).placeId or 0,
	}
end

return {
	game = makeGame,
	workspace = makeWorkspace,
	Instance = makeInstance,
	task = makeTask,
}
