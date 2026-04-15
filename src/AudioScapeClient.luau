--!strict
--[[
	AudioScapeClient — client-side companion for AudioScape SDK.

	Place this module in ReplicatedStorage. Call client:enableClientAccess()
	on the server first to set up the RemoteFunctions.

	Usage (LocalScript):
		local AudioScapeClient = require(ReplicatedStorage.AudioScapeClient)
		local client = AudioScapeClient.new()
		local result, err = client:search({ query = "chill beats" })
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AudioScapeClient = {}
AudioScapeClient.__index = AudioScapeClient

type AudioScapeClientInstance = typeof(setmetatable({} :: {
	_remotes: Folder,
}, AudioScapeClient))

function AudioScapeClient.new(): AudioScapeClientInstance
	local remotes = ReplicatedStorage:WaitForChild("AudioScapeRemotes", 10)
	assert(remotes, "AudioScapeRemotes not found — call client:enableClientAccess() on the server first")

	local self = setmetatable({
		_remotes = remotes :: Folder,
	}, AudioScapeClient)

	return self
end

local function invoke(remotes: Folder, name: string, ...): (any, string?)
	local remote = remotes:FindFirstChild(name)
	if not remote or not remote:IsA("RemoteFunction") then
		return nil, name .. " remote not available"
	end

	local ok, result, err = pcall(remote.InvokeServer, remote :: RemoteFunction, ...)
	if not ok then
		return nil, "Request failed: " .. tostring(result)
	end

	return result, err
end

-- Search the catalog using natural language.
function AudioScapeClient.search(self: AudioScapeClientInstance, options: { query: string, limit: number?, offset: number?, filters: any? })
	return invoke(self._remotes, "Search", options)
end

-- Find tracks that sound similar to a given track.
function AudioScapeClient.similar(self: AudioScapeClientInstance, options: { asset_id: string, limit: number?, offset: number? })
	return invoke(self._remotes, "Similar", options)
end

-- Browse by artist, album, genre, or mood.
function AudioScapeClient.browse(self: AudioScapeClientInstance, options: { type: string, name: string?, limit: number?, offset: number? })
	return invoke(self._remotes, "Browse", options)
end

-- Fetch a configured playlist and its tracks.
function AudioScapeClient.getPlaylist(self: AudioScapeClientInstance, options: { playlist_id: string })
	return invoke(self._remotes, "GetPlaylist", options)
end

-- List all playlists configured for the API key.
function AudioScapeClient.listPlaylists(self: AudioScapeClientInstance)
	return invoke(self._remotes, "ListPlaylists")
end

return AudioScapeClient
