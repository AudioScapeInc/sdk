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

-- Mirrors the AssetIdResolvable union in src/init.luau. Open indexer on the
-- table arm so callers passing existing options-table shapes (extra fields
-- beyond asset_id) typecheck under strict mode.
export type AssetIdResolvable = string | { asset_id: string, [string]: any } | Sound | AudioPlayer

type AudioScapeClientInstance = typeof(setmetatable(
	{} :: {
		_remotes: Folder,
	},
	AudioScapeClient
))

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

-- Mirrored from src/init.luau — kept duplicated to avoid adding a third file
-- to the wally package. Resolution rules and supported shapes are identical.
local function resolveAssetId(input: any): string?
	if input == nil then
		return nil
	end

	local kind = typeof(input)

	if kind == "Instance" then
		local className = input.ClassName
		local raw: any
		if className == "Sound" then
			raw = input.SoundId
		elseif className == "AudioPlayer" then
			raw = input.Asset
		end
		if type(raw) == "string" then
			return string.match(raw, "%d+")
		end
		return nil
	end

	if kind == "string" then
		if string.match(input, "^%d+$") then
			return input
		end
		return string.match(input, "%d+")
	end

	if kind == "table" then
		local id = input.asset_id
		if type(id) == "string" and #id > 0 then
			return id
		end
	end

	return nil
end

-- Search the catalog using natural language.
function AudioScapeClient.search(
	self: AudioScapeClientInstance,
	options: { query: string, limit: number?, offset: number?, filters: any? }
)
	return invoke(self._remotes, "Search", options)
end

-- Find tracks that sound similar to a given track. Polymorphic input —
-- pass an asset_id string, a Track table, a Sound, or an AudioPlayer; pass
-- `extras` when you want limit/offset/filters and didn't use the legacy
-- options-table form.
function AudioScapeClient.similar(
	self: AudioScapeClientInstance,
	input: AssetIdResolvable,
	extras: { limit: number?, offset: number?, filters: any? }?
): (any, string?)
	local assetId = resolveAssetId(input)
	if not assetId then
		return nil, "similar requires an asset_id string, a track table, a Sound, or an AudioPlayer"
	end
	local opts: any = extras or (type(input) == "table" and input or {})
	return invoke(self._remotes, "Similar", {
		asset_id = assetId,
		limit = opts.limit,
		offset = opts.offset,
		filters = opts.filters,
	})
end

-- Search the SFX catalog by free-text query or category browse.
function AudioScapeClient.sfxSearch(
	self: AudioScapeClientInstance,
	options: { query: string?, limit: number?, offset: number?, filters: any? }
)
	return invoke(self._remotes, "SfxSearch", options)
end

-- Find sound effects acoustically similar to a given asset. Polymorphic
-- input — see similar() for the (input, extras?) contract.
function AudioScapeClient.sfxSimilar(
	self: AudioScapeClientInstance,
	input: AssetIdResolvable,
	extras: { limit: number?, offset: number?, filters: any? }?
): (any, string?)
	local assetId = resolveAssetId(input)
	if not assetId then
		return nil, "sfxSimilar requires an asset_id string, a track table, a Sound, or an AudioPlayer"
	end
	local opts: any = extras or (type(input) == "table" and input or {})
	return invoke(self._remotes, "SfxSimilar", {
		asset_id = assetId,
		limit = opts.limit,
		offset = opts.offset,
		filters = opts.filters,
	})
end

-- Fetch the SFX taxonomy hierarchy (broader_category → category → subcategory).
function AudioScapeClient.getSfxTaxonomy(self: AudioScapeClientInstance)
	return invoke(self._remotes, "GetSfxTaxonomy")
end

-- Browse by artist, album, genre, mood, or trending.
function AudioScapeClient.browse(
	self: AudioScapeClientInstance,
	options: { type: string, name: string?, limit: number?, offset: number? }
)
	return invoke(self._remotes, "Browse", options)
end

-- Browse the SFX catalog. v1 only supports type='trending'.
function AudioScapeClient.sfxBrowse(
	self: AudioScapeClientInstance,
	options: { type: string, name: string?, limit: number?, offset: number? }
)
	return invoke(self._remotes, "SfxBrowse", options)
end

-- Fetch a configured playlist and its tracks.
function AudioScapeClient.getPlaylist(self: AudioScapeClientInstance, options: { playlist_id: string })
	return invoke(self._remotes, "GetPlaylist", options)
end

-- List all playlists configured for the API key.
function AudioScapeClient.listPlaylists(self: AudioScapeClientInstance)
	return invoke(self._remotes, "ListPlaylists")
end

-- Fetch beat grid + section structure for a track (beat-sync animations,
-- lighting cues). Polymorphic input — see similar() for the (input, extras?)
-- contract.
function AudioScapeClient.getStructure(self: AudioScapeClientInstance, input: AssetIdResolvable): (any, string?)
	local assetId = resolveAssetId(input)
	if not assetId then
		return nil, "getStructure requires an asset_id string, a track table, a Sound, or an AudioPlayer"
	end
	return invoke(self._remotes, "GetStructure", { asset_id = assetId })
end

return AudioScapeClient
