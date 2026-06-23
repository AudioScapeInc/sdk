--!nocheck
--[[
	TrendingLobbyJukebox Example

	Drop-in lobby music: pull the daily-trending tracks once, queue them
	through the AudioScapeMusicPlayer, and surface the now-playing line on
	a UI label. New players hear what's hot today; existing players see the
	queue cycle as the day's list refreshes.

	Pair with `client:trackVote(asset_id, "up")` from a thumbs-up button to
	feed engagement back into tomorrow's trending list.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local AudioScape = require(ServerScriptService.Packages.AudioScape)

local apiKey = if RunService:IsStudio() then "your-test-key" else HttpService:GetSecret("AudioScapeKey")

local client = AudioScape.new(apiKey)
local musicPlayer = client:createPlayer({ volume = 0.5 })

-- Optional: a StringValue your UI watches for the now-playing label
local nowPlaying = ReplicatedStorage:FindFirstChild("NowPlaying") or Instance.new("StringValue")
nowPlaying.Name = "NowPlaying"
nowPlaying.Parent = ReplicatedStorage

musicPlayer.OnTrackChanged = function(track)
	nowPlaying.Value = if track then string.format("%s — %s", track.artist, track.name) else ""
end

-- `region = "auto"` ranks by activity near this server's location; omit it
-- (or leave regional trending disabled for your key) to get the global list.
local result, err = client:browse({ type = "trending", region = "auto", limit = 50 })
if not result then
	warn("Trending fetch failed:", err)
	return
end

print(string.format("Lobby jukebox: queued %d trending tracks", #result.tracks))
musicPlayer:queue(result.tracks)
musicPlayer:play()
