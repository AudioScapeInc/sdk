--!nocheck
--[[
	AudioScapeMusicPlayer Basic Example

	Searches for music, queues the results, and plays them
	with automatic analytics tracking. No manual trackPlay/trackStop needed.
]]

local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local AudioScape = require(ServerStorage.AudioScape)

local apiKey = if RunService:IsStudio() then "your-test-key" else HttpService:GetSecret("AudioScapeKey")

AudioScape.setApiKey(apiKey)

-- Create a music player
local player = AudioScape:createPlayer({
	volume = 0.5,
})

-- Log track changes
player.OnTrackChanged = function(track)
	if track then
		print(string.format("Now playing: %s — %s", track.artist, track.name))
	else
		print("Playback stopped")
	end
end

player.OnQueueFinished = function()
	print("Queue finished!")
end

-- Search and queue tracks
local result, err = AudioScape:search({ query = "chill lo-fi beats", limit = 10 })
if not result then
	warn("Search failed:", err)
	return
end

print(string.format("Queuing %d tracks", #result.tracks))
player:queue(result.tracks)
player:play()
