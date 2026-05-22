--!strict
-- Unit tests for AudioScapeMusicPlayer — verifies the v0.15.0 migration from
-- legacy `Sound` to the new Roblox Audio API (`AudioPlayer` + `AudioDeviceOutput`
-- + `Wire`), plus the new `getAudioPlayer()` accessor and `PlayerOptions.output`
-- override. Analytics callbacks (trackPlay / trackStop / trackSkip) are
-- exercised through a fake client so we can assert on call shape and timing.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local mockGame = require("./_harness/mockGame")

local function findByClass(created: { any }, className: string): any?
	for _, inst in ipairs(created) do
		if (inst :: any).ClassName == className and not (inst :: any)._destroyed then
			return inst
		end
	end
	return nil
end

local function lastByClass(created: { any }, className: string): any?
	for i = #created, 1, -1 do
		if (created[i] :: any).ClassName == className then
			return created[i]
		end
	end
	return nil
end

local function makeFakeAnalytics()
	local calls: { { kind: string, assetId: string, playerId: any, duration: any } } = {}
	return {
		trackPlay = function(_, assetId, playerId, duration)
			table.insert(calls, { kind = "play", assetId = assetId, playerId = playerId, duration = duration })
		end,
		trackStop = function(_, assetId, playerId, duration)
			table.insert(calls, { kind = "stop", assetId = assetId, playerId = playerId, duration = duration })
		end,
		trackSkip = function(_, assetId, playerId, duration)
			table.insert(calls, { kind = "skip", assetId = assetId, playerId = playerId, duration = duration })
		end,
	},
		calls
end

local function makeTrack(assetId: string, duration: number)
	return {
		asset_id = assetId,
		name = "t-" .. assetId,
		artist = "a",
		album = "alb",
		genre = "Electronic",
		duration = duration,
	}
end

-- Helper that builds a player directly via the SDK's AudioScapeMusicPlayer.new
-- export. We dig it out of the SDK's createPlayer machinery by calling
-- createPlayer with a fake analytics client wrapper.
local function buildPlayer(analytics: any, options: any?)
	-- Load the player module in a fresh env (matches loadSdk's harness).
	local Instance = mockGame.Instance()
	local game = mockGame.game({})
	local workspace = mockGame.workspace()
	local task = mockGame.task()

	local env: { [string]: any } = {
		assert = assert,
		error = error,
		ipairs = ipairs,
		pairs = pairs,
		setmetatable = setmetatable,
		math = math,
		table = table,
		typeof = typeof,
		type = type,
		tostring = tostring,
		game = game,
		workspace = workspace,
		Instance = Instance,
		task = task,
	}
	local chunk = luau.load(fs.readFile("src/AudioScapeMusicPlayer.luau"), { environment = env })
	local Player = chunk()
	local instance = Player.new(analytics, options)
	return instance, (Instance :: any).__created, Instance
end

-- 1) Construction creates an AudioDeviceOutput when no override is supplied
do
	local analytics, _calls = makeFakeAnalytics()
	local player, created = buildPlayer(analytics)

	local output = findByClass(created, "AudioDeviceOutput")
	assert(output ~= nil, "auto-create AudioDeviceOutput on .new")
	assert(findByClass(created, "AudioPlayer") == nil, "no AudioPlayer created until play()")

	player:destroy()
end

-- 2) Construction with PlayerOptions.output skips the auto-create
do
	local analytics, _calls = makeFakeAnalytics()
	-- Pre-build an "AudioEmitter"-shaped fake via a separate Instance shim
	local externalInstance = mockGame.Instance()
	local emitter = (externalInstance :: any).new("AudioEmitter")

	local player, created = buildPlayer(analytics, { output = emitter })
	assert(findByClass(created, "AudioDeviceOutput") == nil, "no AudioDeviceOutput when caller provides output")

	-- Play a track and assert the wire targets the caller's output, not an auto-created one
	player:queue({ makeTrack("111", 30) })
	player:play()
	local wire = findByClass(created, "Wire")
	assert(wire ~= nil, "Wire created during play")
	assert((wire :: any).TargetInstance == emitter, "Wire targets the caller-provided output")

	player:destroy()
	-- caller-owned output must NOT be destroyed by the player
	assert((emitter :: any)._destroyed == nil, "player must not destroy caller-provided output")
end

-- 3) play() creates AudioPlayer + Wire wired to the output, fires trackPlay,
--    sets NowPlaying, calls OnTrackChanged, and AssetId is the ContentId string
do
	local analytics, calls = makeFakeAnalytics()
	local player, created = buildPlayer(analytics)

	local changed: { any } = {}
	player.OnTrackChanged = function(t)
		table.insert(changed, t)
	end

	player:queue({ makeTrack("111", 30), makeTrack("222", 20) })
	player:play()

	local output = findByClass(created, "AudioDeviceOutput")
	local audioPlayer = findByClass(created, "AudioPlayer")
	local wire = findByClass(created, "Wire")

	assert(audioPlayer ~= nil, "AudioPlayer instance created")
	assert(wire ~= nil, "Wire instance created")
	assert((audioPlayer :: any).Asset == "rbxassetid://111", "AudioPlayer.Asset set from track.asset_id")
	assert((audioPlayer :: any).Volume == 0.5, "default volume 0.5 on the AudioPlayer")
	assert((wire :: any).SourceInstance == audioPlayer, "Wire source = AudioPlayer")
	assert((wire :: any).TargetInstance == output, "Wire target = AudioDeviceOutput")
	assert(player.IsPlaying == true, "IsPlaying flips to true")
	assert((player.NowPlaying :: any).asset_id == "111", "NowPlaying set")

	assert(#calls == 1 and calls[1].kind == "play" and calls[1].assetId == "111", "trackPlay fired with asset_id")
	assert(#changed == 1 and (changed[1] :: any).asset_id == "111", "OnTrackChanged fired with track")

	-- getAudioPlayer accessor returns the current AudioPlayer
	assert(player:getAudioPlayer() == audioPlayer, "getAudioPlayer returns the live AudioPlayer")

	-- setVolume updates the live AudioPlayer
	player:setVolume(0.8)
	assert((audioPlayer :: any).Volume == 0.8, "setVolume propagates to AudioPlayer.Volume")
	-- clamp to 0..1
	player:setVolume(5)
	assert((audioPlayer :: any).Volume == 1, "setVolume clamps above 1")

	player:destroy()
end

-- 4) Natural end (Ended signal) advances to the next track and fires trackStop
do
	local analytics, calls = makeFakeAnalytics()
	local player, created = buildPlayer(analytics)

	player:queue({ makeTrack("111", 1), makeTrack("222", 1) })
	player:play()

	local firstAudioPlayer = findByClass(created, "AudioPlayer")
	assert(firstAudioPlayer ~= nil, "first AudioPlayer exists after play()")

	-- Simulate the asset finishing naturally
	local endedSignal = (firstAudioPlayer :: any).Ended
	endedSignal._fire()

	-- After Ended: first AP destroyed, second AP created, trackStop fired for 111,
	-- trackPlay fired for 222
	assert((firstAudioPlayer :: any)._destroyed, "first AudioPlayer destroyed after Ended")
	local secondAudioPlayer = lastByClass(created, "AudioPlayer")
	assert(secondAudioPlayer ~= firstAudioPlayer, "second AudioPlayer created for next track")
	assert((secondAudioPlayer :: any).Asset == "rbxassetid://222", "second track's Asset")

	-- Call sequence: play(111), stop(111), play(222)
	assert(calls[1].kind == "play" and calls[1].assetId == "111", "first call: play(111)")
	assert(calls[2].kind == "stop" and calls[2].assetId == "111", "second call: stop(111) on Ended")
	assert(calls[3].kind == "play" and calls[3].assetId == "222", "third call: play(222) advance")

	player:destroy()
end

-- 5) skip() fires trackSkip and advances; getAudioPlayer is nil when queue empties
do
	local analytics, calls = makeFakeAnalytics()
	local player = buildPlayer(analytics)

	local finished = false
	player.OnQueueFinished = function()
		finished = true
	end

	player:queue({ makeTrack("111", 30) })
	player:play()

	player:skip()

	-- single-track queue + skip → queue finishes
	assert(calls[1].kind == "play" and calls[1].assetId == "111", "first call: play(111)")
	assert(calls[2].kind == "skip" and calls[2].assetId == "111", "second call: skip(111)")
	assert(player.IsPlaying == false, "IsPlaying flips off when queue finishes via skip")
	assert(player.NowPlaying == nil, "NowPlaying cleared when queue finishes")
	assert(finished == true, "OnQueueFinished fires")
	assert(player:getAudioPlayer() == nil, "getAudioPlayer returns nil when not playing")

	player:destroy()
end

-- 6) stop() fires trackStop, tears down AudioPlayer + Wire, leaves output alive
do
	local analytics, calls = makeFakeAnalytics()
	local player, created = buildPlayer(analytics)

	player:queue({ makeTrack("111", 30) })
	player:play()

	local ap = findByClass(created, "AudioPlayer")
	local wire = findByClass(created, "Wire")
	local output = findByClass(created, "AudioDeviceOutput")

	player:stop()

	assert(calls[#calls].kind == "stop", "stop() fires trackStop")
	assert((ap :: any)._destroyed, "AudioPlayer destroyed on stop")
	assert((wire :: any)._destroyed, "Wire destroyed on stop")
	assert((output :: any)._destroyed == nil, "AudioDeviceOutput survives stop()")
	assert(player:getAudioPlayer() == nil, "getAudioPlayer nil after stop")

	player:destroy()
	assert((output :: any)._destroyed, "owned AudioDeviceOutput destroyed on player:destroy()")
end

-- 7) destroy() while playing fires a final trackStop (BindToClose flush semantics)
do
	local analytics, calls = makeFakeAnalytics()
	local player, _created = buildPlayer(analytics)

	player:queue({ makeTrack("111", 30) })
	player:play()
	player:destroy()

	local stopCall
	for _, c in ipairs(calls) do
		if c.kind == "stop" then
			stopCall = c
		end
	end
	assert(stopCall ~= nil, "destroy() fires a final trackStop for the in-progress track")
	assert(stopCall.assetId == "111", "final trackStop carries the in-progress asset_id")
end
