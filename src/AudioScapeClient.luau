--!strict
--[[
	AudioScapeClient — client-side companion for AudioScape SDK.

	Place this module in ReplicatedStorage. Call AudioScape:enableClientAccess()
	on the server first to set up the RemoteFunctions.

	Usage (LocalScript):
		local AudioScapeClient = require(ReplicatedStorage.AudioScapeClient)
		local result, err = AudioScapeClient:search({ query = "chill beats" })
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Like the server module, this doubles as a ready-to-use object: call
-- methods on AudioScapeClient directly and the remotes resolve on first use.
-- `.new()` stays supported and resolves eagerly, which is useful when you'd
-- rather fail at startup than at first search.
local AudioScapeClient = {
	_remotes = nil :: Folder?,
}
AudioScapeClient.__index = AudioScapeClient

local REMOTES_MISSING = "AudioScapeRemotes not found — call AudioScape:enableClientAccess() on the server first"

local function getRemotes(self: any): Folder
	if self._remotes then
		return self._remotes
	end
	local remotes = ReplicatedStorage:WaitForChild("AudioScapeRemotes", 10)
	assert(remotes, REMOTES_MISSING)
	self._remotes = remotes
	return remotes :: Folder
end

-- Mirrors the AssetIdResolvable union in src/init.luau. Open indexer on the
-- table arm so callers passing existing options-table shapes (extra fields
-- beyond asset_id) typecheck under strict mode.
export type AssetIdResolvable = string | { asset_id: string, [string]: any } | Sound | AudioPlayer

type AudioScapeClientInstance = typeof(setmetatable(
	{} :: {
		-- Optional because the module itself starts unresolved and fills this
		-- in on first use; .new() populates it up front.
		_remotes: Folder?,
	},
	AudioScapeClient
))

-- Create a separate object. Only needed if you want the remotes resolved
-- eagerly (failing at startup rather than at first call) — otherwise call
-- methods on AudioScapeClient directly.
function AudioScapeClient.new(): AudioScapeClientInstance
	local self = setmetatable({ _remotes = nil :: Folder? }, AudioScapeClient)
	getRemotes(self)
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

-- Search the catalog. Pass `query` for free-text/natural-language search, or
-- `asset_ids` for a direct batch lookup of up to 100 IDs (filters bypassed,
-- results in input order, missing IDs surfaced in `meta.missing_ids`).
function AudioScapeClient.search(
	self: AudioScapeClientInstance,
	options: {
		query: string?,
		asset_ids: { string }?,
		limit: number?,
		offset: number?,
		filters: any?,
		region: string?,
		sort: string?,
	}
)
	return invoke(getRemotes(self), "Search", options)
end

-- Sugar over AudioScape:search for known-asset-ID batch lookups.
-- Equivalent to AudioScape:search({ asset_ids = options.asset_ids }).
function AudioScapeClient.lookup(self: AudioScapeClientInstance, options: { asset_ids: { string } }): (any, string?)
	if type(options) ~= "table" or type(options.asset_ids) ~= "table" or #options.asset_ids == 0 then
		return nil, "lookup requires a non-empty asset_ids array of numeric strings"
	end
	return invoke(getRemotes(self), "Search", { asset_ids = options.asset_ids })
end

-- Find tracks that sound similar to a given track. Polymorphic input —
-- pass an asset_id string, a Track table, a Sound, or an AudioPlayer; pass
-- `extras` when you want limit/offset/filters and didn't use the legacy
-- options-table form. `max_score`/`dedupe` filter near-duplicate matches
-- of the seed track from the results.
function AudioScapeClient.similar(
	self: AudioScapeClientInstance,
	input: AssetIdResolvable,
	extras: {
		limit: number?,
		offset: number?,
		filters: any?,
		max_score: number?,
		dedupe: boolean?,
	}?
): (any, string?)
	local assetId = resolveAssetId(input)
	if not assetId then
		return nil, "similar requires an asset_id string, a track table, a Sound, or an AudioPlayer"
	end
	local opts: any = extras or (type(input) == "table" and input or {})
	return invoke(getRemotes(self), "Similar", {
		asset_id = assetId,
		limit = opts.limit,
		offset = opts.offset,
		filters = opts.filters,
		max_score = opts.max_score,
		dedupe = if opts.dedupe == true then true else nil,
	})
end

-- Search the SFX catalog by free-text query or category browse.
function AudioScapeClient.sfxSearch(
	self: AudioScapeClientInstance,
	options: { query: string?, limit: number?, offset: number?, sort: string?, filters: any? }
)
	return invoke(getRemotes(self), "SfxSearch", options)
end

-- Find sound effects acoustically similar to a given asset. Polymorphic
-- input — see similar() for the (input, extras?) contract. `max_score`/
-- `dedupe` filter near-duplicate matches of the seed sound — common in
-- SFX libraries with many uploads of the same generic clip.
function AudioScapeClient.sfxSimilar(
	self: AudioScapeClientInstance,
	input: AssetIdResolvable,
	extras: {
		limit: number?,
		offset: number?,
		filters: any?,
		max_score: number?,
		dedupe: boolean?,
	}?
): (any, string?)
	local assetId = resolveAssetId(input)
	if not assetId then
		return nil, "sfxSimilar requires an asset_id string, a track table, a Sound, or an AudioPlayer"
	end
	local opts: any = extras or (type(input) == "table" and input or {})
	return invoke(getRemotes(self), "SfxSimilar", {
		asset_id = assetId,
		limit = opts.limit,
		offset = opts.offset,
		filters = opts.filters,
		max_score = opts.max_score,
		dedupe = if opts.dedupe == true then true else nil,
	})
end

-- Fetch the SFX taxonomy hierarchy (broader_category → category → subcategory).
function AudioScapeClient.getSfxTaxonomy(self: AudioScapeClientInstance)
	return invoke(getRemotes(self), "GetSfxTaxonomy")
end

-- Browse by artist, album, genre, mood, or trending. `sort` defaults to
-- "popular" server-side; pass "alpha" or "recent" for drill-downs that
-- need fresh uploads instead of engagement ranking.
function AudioScapeClient.browse(
	self: AudioScapeClientInstance,
	options: {
		type: string,
		name: string?,
		limit: number?,
		offset: number?,
		sort: string?,
		region: string?,
	}
)
	return invoke(getRemotes(self), "Browse", options)
end

-- Browse the SFX catalog. v1 only supports type='trending'.
function AudioScapeClient.sfxBrowse(
	self: AudioScapeClientInstance,
	options: { type: string, name: string?, limit: number?, offset: number?, region: string? }
)
	return invoke(getRemotes(self), "SfxBrowse", options)
end

-- Fetch a configured playlist and its tracks.
function AudioScapeClient.getPlaylist(self: AudioScapeClientInstance, options: { playlist_id: string })
	return invoke(getRemotes(self), "GetPlaylist", options)
end

-- List all playlists configured for the API key.
function AudioScapeClient.listPlaylists(self: AudioScapeClientInstance)
	return invoke(getRemotes(self), "ListPlaylists")
end

-- Native SearchAudioAsync returns 30 results per page; match it so paging
-- through the shim behaves the same as paging through the real service.
local NATIVE_AUDIO_PAGE_SIZE = 30

-- Mirrors AssetServiceOptions in src/init.luau.
export type AssetServiceOptions = {
	-- When the AudioScape request fails, fall through to the real
	-- AssetService:SearchAudioAsync instead of erroring. On by default.
	fallback: boolean?,
	-- Results per page. Defaults to native's 30.
	limit: number?,
}

-- An AudioSearchParams Instance can't cross a RemoteFunction by reference, so
-- read its properties into a plain table. AudioSubType travels as its Name —
-- the server accepts either form.
local function paramsToTable(params: any): { [string]: any }
	if type(params) == "table" then
		return params
	end
	local subType = params.AudioSubType
	return {
		SearchKeyword = params.SearchKeyword,
		Title = params.Title,
		Artist = params.Artist,
		Album = params.Album,
		Tag = params.Tag,
		MinDuration = params.MinDuration,
		MaxDuration = params.MaxDuration,
		AudioSubType = if typeof(subType) == "EnumItem" then subType.Name else tostring(subType),
	}
end

-- Client-side drop-in for game:GetService("AssetService"). SearchAudioAsync
-- goes through the SearchAudio remote (HttpService is server-only, so the
-- request and the result mapping both live there); every other member forwards
-- to the real service. Mirrors AudioScape.getAssetService in src/init.luau —
-- kept duplicated rather than shared to avoid adding a file to the wally
-- package, same trade-off as resolveAssetId above.
function AudioScapeClient.getAssetService(self: AudioScapeClientInstance, options: AssetServiceOptions?)
	local opts: AssetServiceOptions = options or {}
	local useFallback = opts.fallback ~= false
	local pageSize = opts.limit or NATIVE_AUDIO_PAGE_SIZE
	local remotes = getRemotes(self)

	local shim = {} :: any

	function shim.SearchAudioAsync(_, params: any): any
		local isInstance = typeof(params) == "Instance"
		assert(isInstance or type(params) == "table", "SearchAudioAsync requires an AudioSearchParams")
		local payload = paramsToTable(params)

		local lastError: string? = nil
		local function fetchPage(offset: number): ({ any }, number)
			local result, err = invoke(remotes, "SearchAudio", payload, offset, pageSize)
			if not result then
				lastError = err or "search failed"
				error(lastError, 0)
			end
			return result.page or {}, tonumber(result.total) or 0
		end

		local ok, pagesOrErr = pcall(function()
			local offset = 0
			local page, total = fetchPage(offset)

			local pages = {} :: any
			pages.IsFinished = #page == 0 or (offset + #page) >= total

			function pages.GetCurrentPage(): { any }
				return page
			end

			function pages.AdvanceToNextPageAsync()
				assert(not pages.IsFinished, "AudioPages: no more pages to advance to")
				offset += pageSize
				page, total = fetchPage(offset)
				pages.IsFinished = #page == 0 or (offset + #page) >= total
			end

			return pages
		end)

		if ok then
			return pagesOrErr
		end

		-- AssetService:SearchAudioAsync carries no security context, so the
		-- client can fall back to it directly.
		if useFallback and isInstance then
			local nativeOk, native = pcall(function()
				return game:GetService("AssetService"):SearchAudioAsync(params)
			end)
			if nativeOk then
				return native
			end
		end

		error(tostring(lastError or pagesOrErr), 0)
	end

	shim.SearchAudio = shim.SearchAudioAsync

	return setmetatable(shim, {
		__index = function(_, key: any): any
			local realService = game:GetService("AssetService")
			local member = (realService :: any)[key]
			if type(member) == "function" then
				return function(_, ...)
					return member(realService, ...)
				end
			end
			return member
		end,
	})
end

-- Fetch beat grid + section structure for a track (beat-sync animations,
-- lighting cues). Polymorphic input — see similar() for the (input, extras?)
-- contract.
function AudioScapeClient.getStructure(self: AudioScapeClientInstance, input: AssetIdResolvable): (any, string?)
	local assetId = resolveAssetId(input)
	if not assetId then
		return nil, "getStructure requires an asset_id string, a track table, a Sound, or an AudioPlayer"
	end
	return invoke(getRemotes(self), "GetStructure", { asset_id = assetId })
end

return AudioScapeClient
