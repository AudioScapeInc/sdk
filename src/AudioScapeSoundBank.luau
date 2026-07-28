--!strict
--[[
	AudioScapeSoundBank — turns one asset ID into a pool of related ones.

	The problem it solves is the "machine gun" effect: a footstep or impact
	that plays the identical clip every time reads as obviously synthetic.
	The usual fix is hand-picking five assets and calling math.random. Here you
	give the asset you already have, and the bank expands it into its
	neighbourhood in the catalog.

	    local bank = AudioScape:createSoundBank({
	        seeds = { footstep = "rbxassetid://1837879082" },
	        kind = "sfx",
	    })
	    bank:resolveAsync()
	    local assetId = bank:pick("footstep")   -- never twice in a row

	Resolution happens once, in as few requests as possible, and every runtime
	pick after that is a local table lookup. That matters: Roblox caps a server
	at 500 HTTP requests per minute, so resolving per-play would exhaust the
	budget almost immediately.
]]

-- /v1/search caps an asset_ids lookup at 100; GetAudioMetadataAsync caps at 30.
local LOOKUP_BATCH_SIZE = 100
local METADATA_BATCH_SIZE = 30

local DEFAULT_POOL_SIZE = 8

-- The catalog client, structurally rather than by import — same duck-typing
-- approach AudioScapeMusicPlayer uses for its analytics dependency, so this
-- module stays independent of init.luau's concrete type.
type CatalogClient = {
	getPlaylist: (self: any, options: any) -> (any, string?),
	lookup: (self: any, options: any) -> (any, string?),
	search: (self: any, options: any) -> (any, string?),
	sfxSearch: (self: any, options: any) -> (any, string?),
	similar: (self: any, input: any, extras: any?) -> (any, string?),
	sfxSimilar: (self: any, input: any, extras: any?) -> (any, string?),
	trackCustom: (self: any, eventType: string, assetId: string?, playerId: any?, metadata: any?) -> (),
}

export type SoundBankOptions = {
	-- Named seeds: { footstep = "rbxassetid://123", impact = "456" }.
	-- Provide these or `playlist_id`, not both.
	seeds: { [string]: string }?,
	-- Build the bank from a sound bank curated in the portal. Each slot becomes
	-- a pool of exactly the sounds chosen for it, so the sounds a game plays can
	-- change without shipping code.
	playlist_id: string?,
	-- "sfx" (default) expands through the sound-effects catalog; "music"
	-- through the music catalog.
	kind: string?,
	-- How many assets to end up with per seed. Default 8.
	poolSize: number?,
	-- "extend" (default) keeps your asset in the pool and adds neighbours
	-- around it. "replace" builds the pool from neighbours only — opt into
	-- that when you genuinely don't care which specific clip plays.
	mode: string?,
	playerId: number?,
}

export type SoundBankPool = {
	name: string,
	seed_asset_id: string,
	-- Where the pool came from: "catalog" (the seed itself is in our catalog),
	-- "bridged" (matched via the engine's metadata for the seed), "none"
	-- (couldn't resolve — pool is just the seed), or "playlist" (curated in the
	-- portal and used exactly as chosen).
	source: string,
	assets: { string },
}

export type SoundBankInstance = {
	Pools: { [string]: SoundBankPool },
	IsResolved: boolean,
	resolveAsync: (self: SoundBankInstance) -> (boolean, string?),
	pick: (self: SoundBankInstance, name: string) -> string?,
	getPool: (self: SoundBankInstance, name: string) -> { string },
	reportUnavailable: (self: SoundBankInstance, assetId: string) -> boolean,
	flushPickCounts: (self: SoundBankInstance) -> (),
	destroy: (self: SoundBankInstance) -> (),
}

local AudioScapeSoundBank = {}
AudioScapeSoundBank.__index = AudioScapeSoundBank

-- Mirrors resolveAssetId in src/init.luau for the string case only — a bank's
-- seeds are always plain IDs or content strings, never Instances.
local function normalizeId(raw: string): string?
	if type(raw) ~= "string" then
		return nil
	end
	return string.match(raw, "%d+")
end

function AudioScapeSoundBank.new(catalog: CatalogClient, options: SoundBankOptions): SoundBankInstance
	assert(type(options) == "table", "createSoundBank requires an options table")

	local playlistId = options.playlist_id
	if playlistId ~= nil then
		assert(type(playlistId) == "string" and #playlistId > 0, "createSoundBank playlist_id must be a non-empty string")
		assert(options.seeds == nil, "createSoundBank takes seeds or playlist_id, not both")
	else
		assert(type(options.seeds) == "table", "createSoundBank requires a seeds table or a playlist_id")
	end

	local kind = options.kind or "sfx"
	assert(kind == "sfx" or kind == "music", 'createSoundBank kind must be "sfx" or "music"')

	local mode = options.mode or "extend"
	assert(mode == "extend" or mode == "replace", 'createSoundBank mode must be "extend" or "replace"')

	local seeds: { [string]: string } = {}
	local names: { string } = {}
	-- Annotated rather than inlined: `options.seeds or {}` infers a union with a
	-- sealed empty table, which Luau then refuses to iterate.
	local rawSeeds: { [string]: string } = options.seeds or {}
	for name, raw in rawSeeds do
		local id = normalizeId(raw)
		assert(id, "seed '" .. tostring(name) .. "' is not a usable asset id: " .. tostring(raw))
		seeds[name] = id
		table.insert(names, name)
	end
	table.sort(names)

	local self = setmetatable({
		Pools = {},
		IsResolved = false,
		_catalog = catalog,
		_seeds = seeds,
		_names = names,
		_playlistId = playlistId,
		_kind = kind,
		_mode = mode,
		_poolSize = math.max(1, options.poolSize or DEFAULT_POOL_SIZE),
		_playerId = options.playerId,
		-- Index of the last pick per pool, so the same asset never lands twice
		-- in a row — the whole point of the exercise.
		_lastIndex = {},
		-- Picks are far too frequent to emit one analytics event each; a
		-- footstep loop would blow through the 500-event buffer in seconds.
		-- Count locally and emit one rolled-up event per flush instead.
		_pickCounts = {},
		_unavailable = {},
	}, AudioScapeSoundBank)

	return (self :: any) :: SoundBankInstance
end

-- Which seeds does the catalog already know? One request per 100 seeds.
function AudioScapeSoundBank._classifySeeds(self: any): ({ [string]: boolean }, string?)
	local ids: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, name in self._names do
		local id = self._seeds[name]
		if not seen[id] then
			seen[id] = true
			table.insert(ids, id)
		end
	end

	local known: { [string]: boolean } = {}
	for start = 1, #ids, LOOKUP_BATCH_SIZE do
		local batch: { string } = {}
		for i = start, math.min(start + LOOKUP_BATCH_SIZE - 1, #ids) do
			table.insert(batch, ids[i])
		end
		local result, err = self._catalog:lookup({ asset_ids = batch, playerId = self._playerId })
		if not result then
			return known, err
		end
		local tracks: { any } = result.tracks or {}
		for _, track in tracks do
			known[tostring(track.asset_id)] = true
		end
	end

	return known, nil
end

-- For seeds the catalog doesn't hold, ask the engine what the asset *is* and
-- search on that. GetAudioMetadataAsync gives Title/Artist for any Roblox
-- audio ID at no cost to us, which is what lets a bank seed off an asset we
-- never ingested. A response carrying only AssetId means Roblox has no
-- metadata either, and the seed can't be bridged.
function AudioScapeSoundBank._bridgeSeeds(self: any, ids: { string }): { [string]: string }
	local anchors: { [string]: string } = {}
	if #ids == 0 then
		return anchors
	end

	for start = 1, #ids, METADATA_BATCH_SIZE do
		local batch: { string } = {}
		for i = start, math.min(start + METADATA_BATCH_SIZE - 1, #ids) do
			table.insert(batch, "rbxassetid://" .. ids[i])
		end

		-- Resolved lazily rather than at module load: only this path needs
		-- AssetService, and requiring it up front would make the whole module
		-- unloadable anywhere the service isn't present.
		local ok, metadata = pcall(function()
			return game:GetService("AssetService"):GetAudioMetadataAsync(batch)
		end)
		if not ok then
			continue
		end

		for _, entry in metadata :: { any } do
			local title = entry.Title
			local artist = entry.Artist
			if type(title) ~= "string" or #title == 0 then
				continue
			end

			local query = if type(artist) == "string" and #artist > 0 then title .. " " .. artist else title
			local result
			if self._kind == "sfx" then
				result = self._catalog:sfxSearch({ query = query, limit = 1, playerId = self._playerId })
			else
				result = self._catalog:search({ query = query, limit = 1, playerId = self._playerId })
			end
			if result and result.tracks and result.tracks[1] then
				anchors[tostring(entry.AssetId)] = tostring(result.tracks[1].asset_id)
			end
		end
	end

	return anchors
end

function AudioScapeSoundBank._neighbours(self: any, anchorId: string): { string }
	local extras = {
		limit = self._poolSize,
		-- Near-identical uploads are the opposite of variation, so drop them.
		dedupe = true,
		playerId = self._playerId,
	}
	local result
	if self._kind == "sfx" then
		result = self._catalog:sfxSimilar(anchorId, extras)
	else
		result = self._catalog:similar(anchorId, extras)
	end

	local ids: { string } = {}
	if result and result.tracks then
		for _, track in result.tracks :: { any } do
			table.insert(ids, tostring(track.asset_id))
		end
	end
	return ids
end

-- Resolve every seed into a pool. Safe to call more than once; it rebuilds.
-- Build pools straight from a portal-curated sound bank.
--
-- Slots are used exactly as chosen — no similarity expansion. The developer
-- already decided what belongs in each slot, and quietly adding sounds they
-- never reviewed is the same mistake as auto-refreshing their gunshot. Widening
-- a slot is a decision made in the portal, where they can hear it first.
function AudioScapeSoundBank._resolveFromPlaylist(self: any): (boolean, string?)
	local result, err = self._catalog:getPlaylist({
		playlist_id = self._playlistId,
		playerId = self._playerId,
	})
	if not result then
		return false, err or "could not load sound bank " .. tostring(self._playlistId)
	end

	local slots = if type(result.playlist) == "table" then result.playlist.slots else nil
	if type(slots) ~= "table" then
		return false, "playlist " .. tostring(self._playlistId) .. " returned no slots"
	end

	local pools: { [string]: SoundBankPool } = {}
	local names: { string } = {}
	for _, slot in slots do
		local label = if type(slot) == "table" then slot.label else nil
		local assetIds = if type(slot) == "table" then slot.asset_ids else nil
		if type(label) == "string" and #label > 0 and type(assetIds) == "table" and #assetIds > 0 then
			local assets: { string } = {}
			for _, raw in assetIds do
				local id = normalizeId(tostring(raw))
				if id then
					table.insert(assets, id)
				end
			end
			if #assets > 0 then
				pools[label] = {
					name = label,
					-- The first sound in the slot stands in as the seed, so the
					-- pool shape matches the seeded path for every consumer.
					seed_asset_id = assets[1],
					source = "playlist",
					assets = assets,
				}
				table.insert(names, label)
			end
		end
	end

	if #names == 0 then
		return false, "playlist " .. tostring(self._playlistId) .. " has no usable slots"
	end

	table.sort(names)
	self._names = names
	self.Pools = pools
	self.IsResolved = true

	self._catalog:trackCustom("audio_resolve", nil, self._playerId, {
		source = "playlist",
		playlist_id = self._playlistId,
		slots = #names,
	})

	return true
end

function AudioScapeSoundBank.resolveAsync(self: any): (boolean, string?)
	if self._playlistId then
		return self:_resolveFromPlaylist()
	end

	local known, err = self:_classifySeeds()
	if err then
		return false, err
	end

	local needBridging: { string } = {}
	local seenUnknown: { [string]: boolean } = {}
	for _, name in self._names do
		local id = self._seeds[name]
		if not known[id] and not seenUnknown[id] then
			seenUnknown[id] = true
			table.insert(needBridging, id)
		end
	end

	local anchors = self:_bridgeSeeds(needBridging)

	local pools: { [string]: SoundBankPool } = {}
	for _, name in self._names do
		local seedId = self._seeds[name]
		local anchorId = if known[seedId] then seedId else anchors[seedId]
		local source = if known[seedId] then "catalog" elseif anchorId then "bridged" else "none"

		local assets: { string } = {}
		local seen: { [string]: boolean } = {}

		-- The developer's own asset leads the pool: we add to their choice
		-- rather than overriding it.
		--
		-- Replace mode drops the seed only when we resolved it from our own
		-- catalog. A bridged or unresolved seed may be audio that's private to
		-- this experience — we can't confirm a substitute is equivalent, and
		-- the developer's game has permission for their asset where a
		-- replacement might not. Silently swapping it out is the one outcome
		-- worse than not helping.
		local keepSeed = self._mode == "extend" or source ~= "catalog"
		if keepSeed then
			assets[1] = seedId
			seen[seedId] = true
		end

		if anchorId then
			for _, id in self:_neighbours(anchorId) do
				if not seen[id] then
					seen[id] = true
					table.insert(assets, id)
				end
				if #assets >= self._poolSize then
					break
				end
			end
		end

		-- Replace mode with nothing to replace with would mean silence.
		-- Falling back to the seed is the only sane outcome.
		if #assets == 0 then
			assets[1] = seedId
		end

		pools[name] = {
			name = name,
			seed_asset_id = seedId,
			source = source,
			assets = assets,
		}

		self._catalog:trackCustom("audio_resolve", seedId, self._playerId, {
			pool = name,
			source = source,
			pool_size = #assets,
			mode = self._mode,
			kind = self._kind,
		})
	end

	self.Pools = pools
	self.IsResolved = true
	return true, nil
end

-- Pick an asset from a pool, never returning the same one twice running.
function AudioScapeSoundBank.pick(self: any, name: string): string?
	local pool = self.Pools[name]
	if not pool then
		return nil
	end

	local candidates: { string } = {}
	for _, id in pool.assets do
		if not self._unavailable[id] then
			table.insert(candidates, id)
		end
	end
	-- Everything in the pool failed to load. Hand back the seed rather than
	-- nothing: the developer's own asset is the best remaining guess.
	if #candidates == 0 then
		return pool.seed_asset_id
	end
	if #candidates == 1 then
		self._pickCounts[candidates[1]] = (self._pickCounts[candidates[1]] or 0) + 1
		return candidates[1]
	end

	local last = self._lastIndex[name]
	local index = math.random(1, #candidates)
	if last and candidates[index] == last then
		-- One deterministic step forward beats re-rolling: it can't loop, and
		-- over many picks the distribution stays even.
		index = (index % #candidates) + 1
	end

	local chosen = candidates[index]
	self._lastIndex[name] = chosen
	self._pickCounts[chosen] = (self._pickCounts[chosen] or 0) + 1
	return chosen
end

function AudioScapeSoundBank.getPool(self: any, name: string): { string }
	local pool = self.Pools[name]
	if not pool then
		return {}
	end
	return table.clone(pool.assets)
end

-- Drop an asset that demonstrably failed to load. Only a client knows this —
-- a headless server never fetches audio, so GetAssetFetchStatus stays None
-- there forever. Report it up and every subsequent pick avoids it.
function AudioScapeSoundBank.reportUnavailable(self: any, assetId: string): boolean
	local id = normalizeId(assetId)
	if not id or self._unavailable[id] then
		return false
	end
	self._unavailable[id] = true
	self._catalog:trackCustom("audio_unavailable", id, self._playerId, { kind = self._kind })
	return true
end

-- Emit accumulated picks as one event per asset instead of one per pick.
function AudioScapeSoundBank.flushPickCounts(self: any)
	for assetId, count in self._pickCounts do
		self._catalog:trackCustom("audio_pick", assetId, self._playerId, {
			count = count,
			kind = self._kind,
		})
	end
	self._pickCounts = {}
end

function AudioScapeSoundBank.destroy(self: any)
	self:flushPickCounts()
	self.Pools = {}
	self.IsResolved = false
end

return AudioScapeSoundBank
