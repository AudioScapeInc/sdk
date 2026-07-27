--!strict
-- Loads `src/init.luau` (and its sibling modules) in a Lune environment
-- with `game`, `workspace`, `Instance`, `task`, and a custom `require`
-- that resolves `script.AudioScapeMusicPlayer` / `script.AudioScapeClient`
-- to file loads.
--
-- Sets `_G.__AUDIOSCAPE_TEST` before loading so the SDK's gated `__internal`
-- export becomes available for tests that need access to module-local
-- helpers.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local mockGame = require("./mockGame")

export type LoadOpts = {
	http: any,
	-- Override individual services if needed (e.g. real HTTP integration tests
	-- still want a stub Players). Leave nil for defaults.
	services: mockGame.Services?,
	gameId: number?,
	placeId: number?,
	-- When true, replaces `warn` in the loaded SDK's environment with a recorder
	-- (no console output). Tests that exercise the SDK's error paths — the
	-- analytics flush retry/backoff code in particular — opt in so the expected
	-- warn lines don't pollute test output. Captured warnings are returned via
	-- the second value from loadSdk so tests can still assert on them.
	silent: boolean?,
}

local function makeBaseEnv(envOverrides: { [string]: any }): { [string]: any }
	local env: { [string]: any } = {
		assert = assert,
		error = error,
		ipairs = ipairs,
		next = next,
		pairs = pairs,
		pcall = pcall,
		xpcall = xpcall,
		print = print,
		warn = warn,
		rawget = rawget,
		rawset = rawset,
		rawequal = rawequal,
		rawlen = rawlen,
		select = select,
		setmetatable = setmetatable,
		getmetatable = getmetatable,
		tonumber = tonumber,
		tostring = tostring,
		type = type,
		typeof = typeof,
		unpack = (table :: any).unpack,
		math = math,
		string = string,
		table = table,
		os = os,
		coroutine = coroutine,
		bit32 = bit32,
		utf8 = utf8,
		buffer = buffer,
		-- selene: allow(global_usage)
		_G = _G,
	}
	for k, v in envOverrides do
		env[k] = v
	end
	return env
end

local function loadFile(filePath: string, env: any): any
	local source = fs.readFile(filePath)
	local chunk = luau.load(source, { environment = env })
	return chunk()
end

local function loadSdk(opts: LoadOpts): (any, { string }, { any })
	assert(opts and opts.http, "loadSdk requires opts.http (mockHttp or realHttp instance)")

	-- selene: allow(global_usage)
	_G.__AUDIOSCAPE_TEST = true

	local services: mockGame.Services = opts.services or {}
	services.HttpService = opts.http

	local game = mockGame.game(services, { gameId = opts.gameId, placeId = opts.placeId })
	local workspace = mockGame.workspace()
	local Instance = mockGame.Instance()
	local task = mockGame.task()

	-- Capture warnings instead of printing them when silent. Tests that
	-- exercise expected warn paths set silent=true to keep output clean and
	-- can still assert on the recorded list afterwards.
	local recordedWarnings: { string } = {}
	local warnFn: (...any) -> ()
	if opts.silent then
		warnFn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring(select(i, ...))
			end
			table.insert(recordedWarnings, table.concat(parts, " "))
		end
	else
		warnFn = warn
	end

	-- Pre-create script tables. The custom require below identifies which
	-- file to load by table identity (not by name), so we hand the SAME
	-- table to both the parent's `script.X` lookup and the require call.
	local playerScript = { Name = "AudioScapeMusicPlayer" }
	local clientScript = { Name = "AudioScapeClient" }
	local soundBankScript = { Name = "AudioScapeSoundBank" }
	local rootScript: { [string]: any } = {
		Name = "AudioScape",
		AudioScapeMusicPlayer = playerScript,
		AudioScapeClient = clientScript,
		AudioScapeSoundBank = soundBankScript,
	}

	local subBase = {
		game = game,
		workspace = workspace,
		Instance = Instance,
		task = task,
		warn = warnFn,
	}

	local function customRequire(target: any): any
		if type(target) == "string" and target:sub(1, 6) == "@lune/" then
			-- luau-lsp can't statically resolve a dynamic alias path; we know it's
			-- always a valid @lune/* import here because of the prefix check above.
			return (require :: any)(target)
		end
		if target == playerScript then
			local env = makeBaseEnv(subBase)
			env.script = playerScript
			env.require = customRequire
			return loadFile("src/AudioScapeMusicPlayer.luau", env)
		end
		if target == soundBankScript then
			local env = makeBaseEnv(subBase)
			env.script = soundBankScript
			env.require = customRequire
			return loadFile("src/AudioScapeSoundBank.luau", env)
		end
		if target == clientScript then
			local env = makeBaseEnv(subBase)
			env.script = clientScript
			env.require = customRequire
			return loadFile("src/AudioScapeClient.luau", env)
		end
		error("loadSdk customRequire: unresolvable target " .. tostring(target), 2)
	end

	local initEnv = makeBaseEnv(subBase)
	initEnv.script = rootScript
	initEnv.require = customRequire

	return loadFile("src/init.luau", initEnv), recordedWarnings, (Instance :: any).__created
end

return {
	loadSdk = loadSdk,
}
