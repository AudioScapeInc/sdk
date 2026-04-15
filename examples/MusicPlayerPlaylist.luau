--!strict
--[[
	AudioScapeMusicPlayer Playlist Example

	Fetches a configured playlist from the portal and plays it
	using the AudioScapeMusicPlayer. Skip/stop analytics are tracked automatically.
]]

local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local AudioScape = require(ServerStorage.AudioScape)

local apiKey = if RunService:IsStudio()
	then "your-test-key"
	else HttpService:GetSecret("AudioScapeKey")

local client = AudioScape.new(apiKey)
local player = client:createPlayer({ volume = 0.5 })

-- Fetch playlists
local list, listErr = client:listPlaylists()
if not list or #list.playlists == 0 then
	warn("No playlists found:", listErr or "none configured")
	return
end

-- Fetch the first playlist
local playlistInfo = list.playlists[1]
print(string.format("Loading playlist: %s (%s)", playlistInfo.name, playlistInfo.genre))

local result, err = client:getPlaylist({ playlist_id = playlistInfo.id })
if not result then
	warn("Failed to fetch playlist:", err)
	return
end

-- Shuffle if the playlist is configured for it
local tracks = result.tracks
if result.playlist.playback_mode == "shuffle" then
	for i = #tracks, 2, -1 do
		local j = math.random(i)
		tracks[i], tracks[j] = tracks[j], tracks[i]
	end
end

-- Queue and play — analytics are automatic
player.OnTrackChanged = function(track)
	if track then
		print(string.format("Now playing: %s — %s", track.artist, track.name))
	end
end

player:queue(tracks)
player:play()
