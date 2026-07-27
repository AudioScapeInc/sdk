--!nocheck
--[[
	PlaylistStation Example

	Lists configured playlists, fetches the first one,
	and plays its tracks in order (or shuffled) via SoundService.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local AudioScape = require(ServerScriptService.Packages.AudioScape)

local apiKey = if RunService:IsStudio() then "your-test-key" else HttpService:GetSecret("AudioScapeKey")

AudioScape.setApiKey(apiKey)

-- Step 1: List all playlists for this API key
local list, listErr = AudioScape:listPlaylists()
if not list or #list.playlists == 0 then
	warn("No playlists found:", listErr or "none configured")
	return
end

print("Your playlists:")
for _, p in list.playlists do
	print(string.format("  %s [%s] — %d tracks (%s)", p.name, p.genre, p.track_count, p.playback_mode))
end

-- Step 2: Fetch the first playlist's tracks
local playlistInfo = list.playlists[1]
local result, err = AudioScape:getPlaylist({ playlist_id = playlistInfo.id })
if not result then
	warn("Failed to fetch playlist:", err)
	return
end

-- Step 3: Optionally shuffle tracks
local tracks = result.tracks
if result.playlist.playback_mode == "shuffle" then
	-- Fisher-Yates shuffle
	for i = #tracks, 2, -1 do
		local j = math.random(i)
		tracks[i], tracks[j] = tracks[j], tracks[i]
	end
end

-- Step 4: Play tracks sequentially
for _, track in tracks do
	print(string.format("Now playing: %s - %s", track.artist, track.name))

	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. track.asset_id
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Wait()
	sound:Destroy()
end

print("Playlist finished!")
