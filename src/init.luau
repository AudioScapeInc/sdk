--!strict

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local AudioScapeMusicPlayer = require(script.AudioScapeMusicPlayer)

local DEFAULT_BASE_URL = "https://api.audioscape.ai/developer"
local DEFAULT_ANALYTICS_URL = "https://api.audioscape.ai/analytics"

local VALID_BROWSE_TYPES = {
	artist = true,
	album = true,
	genre = true,
	mood = true,
	trending = true,
}

local VALID_SFX_BROWSE_TYPES = {
	trending = true,
}

-- Default analytics settings
local DEFAULT_BATCH_INTERVAL = 30 -- seconds
local DEFAULT_MAX_BATCH_SIZE = 50 -- events per flush
local DEFAULT_MAX_QUEUE_SIZE = 500 -- max buffered events before oldest are dropped

export type SearchOptions = {
	-- Required when `asset_ids` is omitted. Free-text query (artist, mood,
	-- genre, description). Two special shapes also short-circuit to a direct
	-- asset-ID lookup: a single numeric string ("12345") or a comma-delimited
	-- list ("123,456,789"). Single-ID-via-query falls through to text search
	-- if not found; the explicit `asset_ids` array does not.
	query: string?,
	-- Explicit batch asset-ID lookup. Up to 100 numeric strings. When
	-- present, takes priority over `query` and bypasses all `filters`.
	-- Returned tracks preserve input order; IDs that don't exist (or are
	-- deleted/delisted/non-public) appear in `meta.missing_ids`.
	asset_ids: { string }?,
	limit: number?,
	offset: number?,
	playerId: number?,
	-- Scope results to a region: "auto" (auto-detect from the server's
	-- location) or an explicit "americas" | "eu" | "apac". Omit for the
	-- global list. Requires regional trending to be enabled for your API key.
	region: string?,
	-- Result ordering: "relevance" (default — best semantic match), "popular"
	-- (most-played first), or "recent" (newest first). Omit for relevance.
	-- Ignored for asset_ids lookups.
	sort: string?,
	filters: {
		-- Each entry accepts the AudioScape canonical name ("Hip Hop / Rap"),
		-- the URL-safe slug ("hip-hop-rap"), or a legacy Roblox music_genre
		-- slug ("hip-hop") — all resolve to the canonical taxonomy. Round-
		-- trip a `track.genre_slug` from a previous response back into here
		-- to filter on that genre.
		genres: { string }?,
		duration: {
			min: number?,
			max: number?,
		}?,
		min_play_count: number?,
		min_likes: number?,
		created_after: string?,
	}?,
}

-- Convenience options for AudioScape:lookup — sugar around AudioScape:search with
-- only asset_ids set. asset_ids is the only required field; limit/offset are
-- accepted for API-shape consistency (filters are not — explicit ID lookups
-- bypass all filters).
export type LookupOptions = {
	asset_ids: { string },
	playerId: number?,
}

export type SimilarOptions = {
	asset_id: string,
	limit: number?,
	offset: number?,
	playerId: number?,
	filters: {
		genres: { string }?,
		duration: {
			min: number?,
			max: number?,
		}?,
	}?,
}

export type SfxSearchOptions = {
	query: string?,
	limit: number?,
	offset: number?,
	playerId: number?,
	-- Result ordering: "relevance" (default), "popular" (most-popular first),
	-- or "recent" (newest first). Omit for relevance.
	sort: string?,
	filters: {
		categories: { string }?,
		subcategories: { string }?,
		duration: {
			min: number?,
			max: number?,
		}?,
		min_likes: number?,
		created_after: string?,
	}?,
}

export type SfxSimilarOptions = {
	asset_id: string,
	limit: number?,
	offset: number?,
	playerId: number?,
	filters: {
		categories: { string }?,
		subcategories: { string }?,
		duration: {
			min: number?,
			max: number?,
		}?,
	}?,
}

-- Anything you can extract an asset_id from. The table arm uses an open
-- indexer so existing options-table callers (StructureOptions, SimilarOptions,
-- SfxSimilarOptions — all have extra fields beyond asset_id) typecheck under
-- strict mode without a sealed-table mismatch.
export type AssetIdResolvable = string | { asset_id: string, [string]: any } | Sound | AudioPlayer

-- "Extras" mirror the legacy *Options shapes minus asset_id. Used as the
-- optional second positional arg in the polymorphic forms — when you pass a
-- Track / Sound / string and still want limit/offset/filters/playerId.
export type StructureExtras = {
	playerId: number?,
}

export type SimilarExtras = {
	limit: number?,
	offset: number?,
	playerId: number?,
	filters: {
		genres: { string }?,
		duration: {
			min: number?,
			max: number?,
		}?,
	}?,
	-- Drops results whose `score` is at or above this value (0..1). Useful
	-- for filtering out near-duplicates of the seed track.
	max_score: number?,
	-- Shortcut: drops near-duplicates of the seed track using a sensible
	-- default threshold. `max_score` takes precedence if both are set.
	dedupe: boolean?,
}

export type SfxSimilarExtras = {
	limit: number?,
	offset: number?,
	playerId: number?,
	filters: {
		categories: { string }?,
		subcategories: { string }?,
		duration: {
			min: number?,
			max: number?,
		}?,
	}?,
	-- Drops results whose `score` is at or above this value (0..1). Useful
	-- for filtering out near-duplicates of the seed sound — common in SFX
	-- libraries with many uploads of the same generic clip.
	max_score: number?,
	-- Shortcut: drops near-duplicates of the seed sound using a sensible
	-- default threshold. `max_score` takes precedence if both are set.
	dedupe: boolean?,
}

export type BrowseOptions = {
	type: string, -- "artist" | "album" | "genre" | "mood" | "trending"
	name: string?,
	-- "popular" (default — popularity ranking, omits tracks with no
	-- engagement), "alpha" (track name A→Z), or "recent" (newest first).
	-- Drill-down only; ignored for list mode and for type = "trending"
	-- (already popularity-ordered). Pick alpha or recent to surface fresh
	-- uploads that haven't accumulated engagement yet.
	sort: string?,
	limit: number?,
	offset: number?,
	playerId: number?,
	-- Scope a trending list to a region: "auto" (auto-detect from the
	-- server's location) or an explicit "americas" | "eu" | "apac". Omit for
	-- the global list. Only affects type = "trending"; requires regional
	-- trending to be enabled for your API key.
	region: string?,
}

export type SfxBrowseOptions = {
	type: string, -- "trending"
	name: string?,
	limit: number?,
	offset: number?,
	playerId: number?,
	-- Scope a trending list to a region: "auto" (auto-detect from the
	-- server's location) or an explicit "americas" | "eu" | "apac". Omit for
	-- the global list. Requires regional trending to be enabled for your API key.
	region: string?,
}

export type Track = {
	asset_id: string,
	name: string,
	artist: string,
	album: string,
	-- Canonical genre from the AudioScape taxonomy (e.g. "Hip Hop / Rap").
	-- Stable across endpoints; use for display.
	genre: string,
	-- URL-safe identifier paired with `genre` (e.g. "hip-hop-rap"). Pass
	-- back into AudioScape:browse({ type = "genre", name = ... }) or into
	-- SearchOptions.filters.genres without URL-encoding.
	genre_slug: string,
	duration: number,
	bpm: number?,
	score: number,
	created_at: string,
	updated_at: string,
}

export type SearchResult = {
	tracks: { Track },
	artists: { { name: string, track_count: number } },
	albums: { { name: string, artist: string, track_count: number } },
	meta: {
		total: number,
		limit: number,
		offset: number,
		-- "semantic" | "text" | "id" | "ids-batch"
		search_method: string,
		matched_artist: string?,
		-- Asset-ID lookup mode only. Lists IDs that didn't match (deleted,
		-- delisted, non-public, never existed). Omitted when empty.
		missing_ids: { string }?,
	},
}

export type SimilarResult = {
	tracks: { Track },
	meta: {
		total: number,
		limit: number,
		offset: number,
	},
}

export type SfxTrack = {
	asset_id: string,
	name: string,
	description: string,
	category: string,
	subcategory: string,
	tags: string,
	duration: number,
	score: number,
	created_at: string,
	updated_at: string,
	creator_id: number?,
	creator_name: string,
}

export type SfxSearchResult = {
	tracks: { SfxTrack },
	categories: { { name: string, track_count: number } },
	subcategories: { { name: string, category: string, track_count: number } },
	meta: {
		total: number,
		limit: number,
		offset: number,
		search_method: string,
		synthesized_query: string?,
	},
}

export type SfxSimilarResult = {
	tracks: { SfxTrack },
	meta: {
		total: number,
		limit: number,
		offset: number,
	},
}

export type SfxTaxonomyCategory = {
	category: string,
	subcategories: { string },
}

export type SfxTaxonomyGroup = {
	broader_category: string,
	categories: { SfxTaxonomyCategory },
}

export type SfxTaxonomyResult = {
	taxonomy: { SfxTaxonomyGroup },
	meta: {
		broader_category_count: number,
		category_count: number,
		subcategory_count: number,
	},
}

export type BrowseListResult = {
	items: { [string]: any },
	meta: {
		total: number,
		limit: number,
		offset: number,
		type: string,
	},
}

-- Typed shape of an item from `AudioScape:browse({ type = "genre" }).items[i]`.
-- BrowseListResult.items stays permissive so other browse types
-- (artist/album/mood) aren't forced through a discriminated union;
-- consumers querying genre items are expected to cast manually:
--
--   local result = AudioScape:browse({ type = "genre" })
--   for _, item in result.items do
--       local genre = item :: AudioScape.BrowseGenreItem
--       print(genre.display_name, "→", genre.slug)
--   end
export type BrowseGenreItem = {
	-- Canonical genre name from the AudioScape taxonomy (e.g. "Hip Hop / Rap").
	name: string,
	-- URL-safe identifier (e.g. "hip-hop-rap"). Pass back into AudioScape:browse
	-- as the `name` parameter to drill into this genre's tracks.
	slug: string,
	-- Display label (currently equal to `name`, may diverge in the future).
	display_name: string,
	track_count: number,
}

export type BrowseTracksResult = {
	tracks: { Track },
	meta: {
		total: number,
		limit: number,
		offset: number,
		type: string,
		-- Present for drill-downs (artist/album/genre/mood) and absent for
		-- trending without an explicit window — same field, different surface.
		name: string?,
	},
}

export type SfxBrowseResult = {
	tracks: { SfxTrack },
	meta: {
		total: number,
		limit: number,
		offset: number,
		type: string,
		name: string?,
	},
}

export type StructureOptions = {
	asset_id: string,
	playerId: number?,
}

export type BeatGrid = {
	times: { number },
	downbeats: { number },
}

export type Section = {
	start: number,
	-- `end` is a reserved Luau keyword; quote it so the type parses. The
	-- AudioScape API returns the field as `end` (matching its snake_case
	-- shape), so consumers must read it via section["end"] as well.
	["end"]: number,
	label: string?,
	energy: number?,
	bar_start: number?,
	bar_end: number?,
	bars: number?,
	color: string?,
}

export type StructureResult = {
	asset_id: string,
	duration: number?,
	bpm: number?,
	track_energy: number?,
	beat_grid: BeatGrid?,
	-- Two structural layers, same shape and label set, differing only in
	-- granularity: `sections` is the finer layer (more, shorter segments),
	-- `phrases` the coarser (fewer, longer). Align long transitions like
	-- crossfades to `phrases`; finer cues to `sections`.
	sections: { Section },
	phrases: { Section },
}

export type BeatHit = {
	index: number,
	time: number,
	beat_num: number,
	is_downbeat: boolean,
}

export type PlaylistOptions = {
	playlist_id: string,
	playerId: number?,
}

export type PlaylistInfo = {
	id: string,
	name: string,
	genre: string,
	playback_mode: string,
	track_count: number,
}

export type PlaylistTrack = {
	asset_id: string,
	name: string,
	artist: string,
	album: string,
	-- Canonical genre from the AudioScape taxonomy (e.g. "Hip Hop / Rap").
	genre: string,
	-- URL-safe identifier paired with `genre` (e.g. "hip-hop-rap").
	genre_slug: string,
	duration: number,
	bpm: number?,
	position: number,
	created_at: string,
	updated_at: string,
}

export type PlaylistResult = {
	playlist: PlaylistInfo,
	tracks: { PlaylistTrack },
	meta: { total: number },
}

export type ListPlaylistsResult = {
	playlists: { PlaylistInfo },
	meta: { total: number },
}

export type AnalyticsConfig = {
	enabled: boolean?,
	batchInterval: number?,
	maxBatchSize: number?,
	maxQueueSize: number?,
}

type AnalyticsEvent = {
	type: string,
	asset_id: string?,
	timestamp: number?,
	player_id: string?,
	duration: number?,
	value: string?,
	metadata: { [string]: any }?,
}

-- The module doubles as a ready-to-use object. `AudioScape.setApiKey(key)`
-- fills in the state below, and every method then works on `AudioScape`
-- directly — so there's nothing to name, and no chance of calling it
-- something that collides with Roblox's own client/server vocabulary.
-- `AudioScape.new(key)` still returns a separate object for the rare
-- multiple-key case and for test isolation.
local AudioScape = {
	_apiKey = nil :: any,
	_baseUrl = DEFAULT_BASE_URL,
	_analyticsUrl = DEFAULT_ANALYTICS_URL,
	_universeId = "",
	_placeId = "",
	_analyticsEnabled = true,
	_analyticsBatchInterval = DEFAULT_BATCH_INTERVAL,
	_analyticsMaxBatchSize = DEFAULT_MAX_BATCH_SIZE,
	_analyticsMaxQueueSize = DEFAULT_MAX_QUEUE_SIZE,
	_analyticsBuffer = {} :: { AnalyticsEvent },
	_analyticsRunning = false,
	_analyticsBackoff = DEFAULT_BATCH_INTERVAL,
	_analyticsConsecutiveFailures = 0,
	_structureCache = {} :: { [string]: StructureResult },
}
AudioScape.__index = AudioScape

-- Named "Instance" rather than "Client" on purpose: in Roblox, "client" means
-- the player's machine, and this object only ever lives on the server. The
-- name `AudioScapeClient` belongs to the LocalScript companion module, where
-- it means what a Roblox developer expects it to mean.
export type AudioScapeInstance = typeof(setmetatable(
	{} :: {
		_apiKey: any,
		_baseUrl: string,
		_analyticsUrl: string,
		_universeId: string,
		_placeId: string,
		_analyticsEnabled: boolean,
		_analyticsBatchInterval: number,
		_analyticsMaxBatchSize: number,
		_analyticsMaxQueueSize: number,
		_analyticsBuffer: { AnalyticsEvent },
		_analyticsRunning: boolean,
		_analyticsBackoff: number,
		_analyticsConsecutiveFailures: number,
		_structureCache: { [string]: StructureResult },
	},
	AudioScape
))

-- Compute the next analytics-flush wait given how many consecutive failures
-- have happened. Doubles each failure, capped at 300s. `failures = 0` returns
-- the steady-state interval.
local ANALYTICS_BACKOFF_CAP = 300
local function computeAnalyticsBackoff(consecutiveFailures: number, batchInterval: number): number
	if consecutiveFailures <= 0 then
		return batchInterval
	end
	return math.min(batchInterval * (2 ^ consecutiveFailures), ANALYTICS_BACKOFF_CAP)
end

local function formatError(statusCode: number, body: string): string
	if statusCode == 401 then
		return "Invalid API key (401)"
	elseif statusCode == 429 then
		return "Rate limited — too many requests (429)"
	elseif statusCode >= 500 then
		return "Server error — try again later (" .. tostring(statusCode) .. ")"
	end

	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, body)
	if ok and type(decoded) == "table" and decoded.error then
		return tostring(decoded.error) .. " (" .. tostring(statusCode) .. ")"
	end

	return "Request failed (" .. tostring(statusCode) .. ")"
end

-- Resolves a flexible "anything that carries an asset_id" input to the bare
-- numeric id string. Accepts:
--   * "1234" or "rbxassetid://1234" (any string with a digit run)
--   * a Sound instance — peels SoundId
--   * an AudioPlayer instance — peels Asset (the legacy ContentId field;
--     the newer .AudioContent is a Content userdata and is NOT auto-resolved
--     in v0.11.0 — pass `audioPlayer.AudioContent.Uri` yourself for now)
--   * any table with an `asset_id` string field (Track, PlaylistTrack,
--     StructureOptions, SimilarOptions — i.e. either an SDK response row or
--     the existing options table)
-- Returns nil when the shape doesn't match. Order matters: the Instance
-- branch runs before the table branch so a Sound-*shaped* table can't sneak
-- through. Mirrored in src/AudioScapeClient.luau (kept duplicated to avoid
-- adding a third file to the wally package — see CHANGELOG v0.11.0).
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

local function request(
	self: AudioScapeInstance,
	path: string,
	body: { [string]: any },
	playerId: number?
): (any, string?)
	local jsonBody = HttpService:JSONEncode(body)

	local headers: { [string]: any } = {
		["x-api-key"] = self._apiKey,
		["Content-Type"] = "application/json",
		["X-Universe-Id"] = self._universeId,
		["X-Place-Id"] = self._placeId,
	}
	if playerId then
		headers["X-Player-Id"] = tostring(playerId)
	end

	local ok, result = pcall(HttpService.RequestAsync, HttpService, {
		Url = self._baseUrl .. path,
		Method = "POST",
		Headers = headers,
		Body = jsonBody,
	})

	if not ok then
		return nil, "Network error: " .. tostring(result)
	end

	if not result.Success then
		return nil, formatError(result.StatusCode, result.Body)
	end

	local decodeOk, decoded = pcall(HttpService.JSONDecode, HttpService, result.Body)
	if not decodeOk then
		return nil, "Failed to decode response"
	end

	return decoded, nil
end

-- Skips nil values so callers don't need to filter their options table.
-- Tables are JSON-encoded then URL-encoded — the API expects structured
-- `filters` to come through as a single querystring parameter holding the
-- JSON-encoded value (per the GET /v1/similar + /v1/sfx/similar contract).
local function buildQuery(params: { [string]: any }): string
	local parts: { string } = {}
	for key, value in pairs(params) do
		if value ~= nil then
			local encoded
			if type(value) == "table" then
				encoded = HttpService:UrlEncode(HttpService:JSONEncode(value))
			else
				encoded = HttpService:UrlEncode(tostring(value))
			end
			table.insert(parts, key .. "=" .. encoded)
		end
	end
	if #parts == 0 then
		return ""
	end
	return "?" .. table.concat(parts, "&")
end

-- GET sibling of request() for endpoints CloudFront edge-caches
-- (browse, sfxBrowse, sfxTaxonomy, similar, sfxSimilar). Flagged as a v1.0.0
-- cleanup candidate to fold both into one method-aware helper.
local function requestGet(
	self: AudioScapeInstance,
	path: string,
	query: { [string]: any },
	playerId: number?
): (any, string?)
	local headers: { [string]: any } = {
		["x-api-key"] = self._apiKey,
		["X-Universe-Id"] = self._universeId,
		["X-Place-Id"] = self._placeId,
	}
	if playerId then
		headers["X-Player-Id"] = tostring(playerId)
	end

	local ok, result = pcall(HttpService.RequestAsync, HttpService, {
		Url = self._baseUrl .. path .. buildQuery(query),
		Method = "GET",
		Headers = headers,
	})

	if not ok then
		return nil, "Network error: " .. tostring(result)
	end

	if not result.Success then
		return nil, formatError(result.StatusCode, result.Body)
	end

	local decodeOk, decoded = pcall(HttpService.JSONDecode, HttpService, result.Body)
	if not decodeOk then
		return nil, "Failed to decode response"
	end

	return decoded, nil
end

--[[ ──────────────────────────────────────────
     Analytics — internal helpers
     ────────────────────────────────────────── ]]

local function requeueBatch(self: AudioScapeInstance, batch: { AnalyticsEvent })
	for i = #batch, 1, -1 do
		table.insert(self._analyticsBuffer, 1, batch[i])
	end
	-- Trim to maxQueueSize (drop newest un-sent events from the tail)
	while #self._analyticsBuffer > self._analyticsMaxQueueSize do
		table.remove(self._analyticsBuffer)
	end
end

local function flushAnalyticsBuffer(self: AudioScapeInstance): boolean
	if #self._analyticsBuffer == 0 then
		return true
	end

	-- Drain up to maxBatchSize events from the buffer. table.remove returns
	-- T? in strict mode (the table could be empty); we know it isn't because
	-- count <= #buffer, so cast to satisfy the analyzer.
	local batch: { AnalyticsEvent } = {}
	local count = math.min(#self._analyticsBuffer, self._analyticsMaxBatchSize)
	for _ = 1, count do
		table.insert(batch, table.remove(self._analyticsBuffer, 1) :: AnalyticsEvent)
	end

	local jsonBody = HttpService:JSONEncode({ events = batch })

	local headers: { [string]: any } = {
		["x-api-key"] = self._apiKey,
		["Content-Type"] = "application/json",
		["X-Universe-Id"] = self._universeId,
		["X-Place-Id"] = self._placeId,
	}

	local ok, result = pcall(HttpService.RequestAsync, HttpService, {
		Url = self._analyticsUrl .. "/v1/analytics",
		Method = "POST",
		Headers = headers,
		Body = jsonBody,
	})

	if not ok then
		warn("[AudioScape] Analytics flush failed: " .. tostring(result))
		requeueBatch(self, batch)
		return false
	end

	if not result.Success then
		warn("[AudioScape] Analytics flush HTTP " .. tostring(result.StatusCode))
		-- Re-queue on retryable errors; drop on client errors (bad key, bad request, etc.)
		if result.StatusCode == 429 or result.StatusCode >= 500 then
			requeueBatch(self, batch)
		end
		return false
	end

	return true
end

local function startAnalyticsLoop(self: AudioScapeInstance)
	if self._analyticsRunning then
		return
	end
	self._analyticsRunning = true

	-- Flush on game close (best-effort, stop after repeated failures)
	game:BindToClose(function()
		local failures = 0
		while #self._analyticsBuffer > 0 and failures < 3 do
			local ok, result = pcall(flushAnalyticsBuffer, self)
			if not ok or not result then
				failures += 1
			end
		end
	end)

	-- Periodic flush loop with exponential backoff
	task.spawn(function()
		while self._analyticsRunning do
			task.wait(self._analyticsBackoff)
			if self._analyticsEnabled and #self._analyticsBuffer > 0 then
				local ok, result = pcall(flushAnalyticsBuffer, self)
				if not ok then
					warn("[AudioScape] Analytics loop error: " .. tostring(result))
				end

				local flushed = ok and result == true
				if flushed then
					self._analyticsConsecutiveFailures = 0
				else
					self._analyticsConsecutiveFailures += 1
				end
				self._analyticsBackoff = computeAnalyticsBackoff(self._analyticsConsecutiveFailures, self._analyticsBatchInterval)
			end
		end
	end)
end

local function enqueueEvent(self: AudioScapeInstance, event: AnalyticsEvent)
	if not self._analyticsEnabled then
		return
	end

	-- Set timestamp if not provided
	if not event.timestamp then
		event.timestamp = workspace:GetServerTimeNow()
	end

	-- Enforce queue size limit (drop oldest events)
	while #self._analyticsBuffer >= self._analyticsMaxQueueSize do
		table.remove(self._analyticsBuffer, 1)
	end

	table.insert(self._analyticsBuffer, event)
end

--[[ ──────────────────────────────────────────
     Public API
     ────────────────────────────────────────── ]]

-- Shared by setApiKey and new so the two paths can't drift. `target` is
-- either the module table (singleton use) or a fresh table (new).
local function initState(target: any, apiKey: any, caller: string): AudioScapeInstance
	assert(apiKey ~= nil, caller .. " requires an API key (string or Secret)")
	if type(apiKey) == "string" then
		assert(#apiKey > 0, caller .. " requires a non-empty API key string")
	end

	target._apiKey = apiKey
	target._baseUrl = target._baseUrl or DEFAULT_BASE_URL
	target._analyticsUrl = target._analyticsUrl or DEFAULT_ANALYTICS_URL
	-- Universe and Place are properties of the running game, so they're the
	-- same for every object — nothing here is genuinely per-instance except
	-- the key and the analytics settings.
	target._universeId = tostring(game.GameId)
	target._placeId = tostring(game.PlaceId)

	-- Analytics state. Buffer and running-flag are preserved if they already
	-- exist, so calling setApiKey a second time swaps the key without
	-- dropping queued events or spawning a second flush loop.
	target._analyticsEnabled = true
	target._analyticsBatchInterval = DEFAULT_BATCH_INTERVAL
	target._analyticsMaxBatchSize = DEFAULT_MAX_BATCH_SIZE
	target._analyticsMaxQueueSize = DEFAULT_MAX_QUEUE_SIZE
	target._analyticsBuffer = target._analyticsBuffer or {}
	target._analyticsRunning = target._analyticsRunning or false
	target._analyticsBackoff = DEFAULT_BATCH_INTERVAL
	target._analyticsConsecutiveFailures = 0
	target._structureCache = target._structureCache or {}

	-- Start analytics loop on server only
	if RunService:IsServer() and RunService:IsRunning() then
		startAnalyticsLoop(target)
	end

	return target
end

-- Point the module at your API key. After this, call methods on AudioScape
-- itself — `AudioScape:search{...}`, `AudioScape:createPlayer()`.
--
--   local AudioScape = require(ServerScriptService.Packages.AudioScape)
--   AudioScape.setApiKey(HttpService:GetSecret("AudioScapeKey"))
--
-- Accepts a plain string or the Secret userdata from HttpService:GetSecret.
function AudioScape.setApiKey(apiKey: any, colonCallKey: any?): AudioScapeInstance
	-- Tolerate AudioScape:setApiKey(key) as well as AudioScape.setApiKey(key);
	-- the colon form arrives with the module table as the first argument.
	if apiKey == AudioScape then
		apiKey = colonCallKey
	end
	return initState(AudioScape, apiKey, "AudioScape.setApiKey")
end

export type EndpointOptions = {
	-- Base for the developer API. Default "https://api.audioscape.ai/developer".
	baseUrl: string?,
	-- Base for analytics ingest. Default "https://api.audioscape.ai/analytics".
	analyticsUrl: string?,
}

-- Point the SDK at a different API host. You only need this to develop
-- against a locally-running API or a staging environment:
--
--   AudioScape.setEndpoints({
--       baseUrl = "http://localhost:3000/developer",
--       analyticsUrl = "http://localhost:3001/analytics",
--   })
--
-- Studio can reach http://localhost; a published Roblox server cannot, so
-- this is a development affordance rather than a deployment mechanism. Safe
-- to call before or after setApiKey — neither resets the other. Omitted
-- fields keep their current value.
function AudioScape.setEndpoints(options: any, colonCallOptions: EndpointOptions?)
	-- Tolerate AudioScape:setEndpoints{...} as well as the dot form.
	local opts: EndpointOptions = if options == AudioScape then colonCallOptions :: any else options
	assert(type(opts) == "table", "setEndpoints requires a table with baseUrl and/or analyticsUrl")

	if opts.baseUrl ~= nil then
		assert(type(opts.baseUrl) == "string" and #opts.baseUrl > 0, "baseUrl must be a non-empty string")
		-- A trailing slash would produce "…//v1/search", which some gateways
		-- treat as a different route than the one they registered.
		AudioScape._baseUrl = (string.gsub(opts.baseUrl, "/+$", ""))
	end
	if opts.analyticsUrl ~= nil then
		assert(type(opts.analyticsUrl) == "string" and #opts.analyticsUrl > 0, "analyticsUrl must be a non-empty string")
		AudioScape._analyticsUrl = (string.gsub(opts.analyticsUrl, "/+$", ""))
	end
end

-- Create a separate object with its own API key. Only needed when one server
-- must talk to AudioScape under more than one key — otherwise prefer
-- setApiKey and call methods on the module directly.
function AudioScape.new(apiKey: any): AudioScapeInstance
	return initState(setmetatable({}, AudioScape), apiKey, "AudioScape.new")
end

-- Configure analytics settings (call before tracking events)
function AudioScape.configureAnalytics(self: AudioScapeInstance, config: AnalyticsConfig)
	if config.enabled ~= nil then
		self._analyticsEnabled = config.enabled
	end
	if config.batchInterval ~= nil then
		assert(config.batchInterval >= 5, "batchInterval must be at least 5 seconds")
		self._analyticsBatchInterval = config.batchInterval
		self._analyticsBackoff = config.batchInterval
		self._analyticsConsecutiveFailures = 0
	end
	if config.maxBatchSize ~= nil then
		assert(config.maxBatchSize >= 1 and config.maxBatchSize <= 500, "maxBatchSize must be 1-500")
		self._analyticsMaxBatchSize = config.maxBatchSize
	end
	if config.maxQueueSize ~= nil then
		assert(config.maxQueueSize >= 10, "maxQueueSize must be at least 10")
		self._analyticsMaxQueueSize = config.maxQueueSize
	end
end

-- Force flush all buffered analytics events immediately (stops after repeated failures)
function AudioScape.flushAnalytics(self: AudioScapeInstance)
	local failures = 0
	while #self._analyticsBuffer > 0 and failures < 3 do
		local ok, result = pcall(flushAnalyticsBuffer, self)
		if not ok or not result then
			failures += 1
		end
	end
end

--[[ ──────────────────────────────────────────
     Analytics — track events
     ────────────────────────────────────────── ]]

-- Track a song play event
function AudioScape.trackPlay(
	self: AudioScapeInstance,
	assetId: string,
	playerId: (number | string)?,
	duration: number?
)
	enqueueEvent(self, {
		type = "play",
		asset_id = assetId,
		player_id = if playerId then tostring(playerId) else nil,
		duration = duration,
	})
end

-- Track a song stop event (natural end or user action)
function AudioScape.trackStop(
	self: AudioScapeInstance,
	assetId: string,
	playerId: (number | string)?,
	duration: number?
)
	enqueueEvent(self, {
		type = "stop",
		asset_id = assetId,
		player_id = if playerId then tostring(playerId) else nil,
		duration = duration,
	})
end

-- Track a song skip event
function AudioScape.trackSkip(
	self: AudioScapeInstance,
	assetId: string,
	playerId: (number | string)?,
	duration: number?
)
	enqueueEvent(self, {
		type = "skip",
		asset_id = assetId,
		player_id = if playerId then tostring(playerId) else nil,
		duration = duration,
	})
end

-- Track a vote event (value must be "up" or "down")
function AudioScape.trackVote(self: AudioScapeInstance, assetId: string, value: string, playerId: (number | string)?)
	assert(value == "up" or value == "down", "vote value must be 'up' or 'down'")
	enqueueEvent(self, {
		type = "vote",
		asset_id = assetId,
		value = value,
		player_id = if playerId then tostring(playerId) else nil,
	})
end

-- Track a favorite event
function AudioScape.trackFavorite(self: AudioScapeInstance, assetId: string, playerId: (number | string)?)
	enqueueEvent(self, {
		type = "favorite",
		asset_id = assetId,
		player_id = if playerId then tostring(playerId) else nil,
	})
end

-- Track an unfavorite event
function AudioScape.trackUnfavorite(self: AudioScapeInstance, assetId: string, playerId: (number | string)?)
	enqueueEvent(self, {
		type = "unfavorite",
		asset_id = assetId,
		player_id = if playerId then tostring(playerId) else nil,
	})
end

-- Track an add-to-queue event (setlist, playlist, etc.)
function AudioScape.trackAddToQueue(self: AudioScapeInstance, assetId: string, playerId: (number | string)?)
	enqueueEvent(self, {
		type = "add_to_queue",
		asset_id = assetId,
		player_id = if playerId then tostring(playerId) else nil,
	})
end

-- Track a search result click
function AudioScape.trackSearchClick(
	self: AudioScapeInstance,
	assetId: string,
	playerId: (number | string)?,
	metadata: { [string]: any }?
)
	enqueueEvent(self, {
		type = "search_click",
		asset_id = assetId,
		player_id = if playerId then tostring(playerId) else nil,
		metadata = metadata,
	})
end

-- Track a custom event (any string type, flexible schema)
function AudioScape.trackCustom(
	self: AudioScapeInstance,
	eventType: string,
	assetId: string?,
	playerId: (number | string)?,
	metadata: { [string]: any }?
)
	assert(type(eventType) == "string" and #eventType > 0, "custom event type must be a non-empty string")
	enqueueEvent(self, {
		type = eventType,
		asset_id = assetId,
		player_id = if playerId then tostring(playerId) else nil,
		metadata = metadata,
	})
end

--[[ ──────────────────────────────────────────
     Search / Similar / Browse
     ────────────────────────────────────────── ]]

function AudioScape.search(self: AudioScapeInstance, options: SearchOptions): (SearchResult?, string?)
	local hasQuery = type(options.query) == "string" and #options.query > 0
	local hasIds = type(options.asset_ids) == "table" and #options.asset_ids > 0
	if not hasQuery and not hasIds then
		return nil, "search requires either a non-empty query string or a non-empty asset_ids array"
	end

	local body: { [string]: any } = {
		limit = options.limit,
		offset = options.offset,
		filters = options.filters,
		region = options.region,
		sort = options.sort,
	}
	if hasQuery then
		body.query = options.query
	end
	if hasIds then
		body.asset_ids = options.asset_ids
	end

	return request(self, "/v1/search", body, options.playerId)
end

-- Sugar over AudioScape:search for known-asset-ID batch lookups. Equivalent to
-- AudioScape:search({ asset_ids = options.asset_ids, playerId = options.playerId }).
-- Filters intentionally aren't accepted — explicit ID lookups bypass them
-- server-side, and exposing the field here would mislead. Up to 100 IDs.
function AudioScape.lookup(self: AudioScapeInstance, options: LookupOptions): (SearchResult?, string?)
	if type(options) ~= "table" or type(options.asset_ids) ~= "table" or #options.asset_ids == 0 then
		return nil, "lookup requires a non-empty asset_ids array of numeric strings"
	end
	return AudioScape.search(self, {
		asset_ids = options.asset_ids,
		playerId = options.playerId,
	})
end

-- Polymorphic input: pass an asset_id string, a Track-shaped table, a Sound,
-- or an AudioPlayer. `extras` carries limit/offset/filters/playerId; if you
-- pass the legacy options table (`{ asset_id, limit, ... }`) those fields are
-- read from the input itself when `extras` is omitted.
function AudioScape.similar(
	self: AudioScapeInstance,
	input: AssetIdResolvable,
	extras: SimilarExtras?
): (SimilarResult?, string?)
	local assetId = resolveAssetId(input)
	if not assetId then
		return nil, "similar requires an asset_id string, a track table, a Sound, or an AudioPlayer"
	end

	local opts: any = extras or (type(input) == "table" and input or {})

	-- GET so CloudFront edge-caches. dedupe=false is omitted (no point
	-- sending the no-op default — keeps the cache key clean).
	return requestGet(self, "/v1/similar", {
		asset_id = assetId,
		limit = opts.limit,
		offset = opts.offset,
		filters = opts.filters,
		max_score = opts.max_score,
		dedupe = if opts.dedupe == true then true else nil,
	}, opts.playerId)
end

-- Search the SFX catalog. Pass `query` for free-text search, or pass
-- `filters.categories` (with optional `filters.subcategories`) to browse a
-- category — the API auto-injects a curated query so you get good results
-- without needing to know the right search terms.
function AudioScape.sfxSearch(self: AudioScapeInstance, options: SfxSearchOptions): (SfxSearchResult?, string?)
	local hasQuery = type(options.query) == "string" and #options.query > 0
	local hasCategory = options.filters and type(options.filters.categories) == "table" and #options.filters.categories > 0
	if not hasQuery and not hasCategory then
		return nil, "sfxSearch requires either a query string or filters.categories"
	end

	local body: { [string]: any } = {
		query = options.query,
		limit = options.limit,
		offset = options.offset,
		sort = options.sort,
		filters = options.filters,
	}

	return request(self, "/v1/sfx/search", body, options.playerId)
end

-- Fetch the SFX taxonomy hierarchy (broader_category → category → subcategory)
-- so you can build pill UIs that mirror filters.categories / .subcategories on
-- /v1/sfx/search. The API caches the response for 10 minutes.
function AudioScape.getSfxTaxonomy(self: AudioScapeInstance): (SfxTaxonomyResult?, string?)
	return requestGet(self, "/v1/sfx/taxonomy", {}, nil)
end

-- Find sound effects acoustically similar to a given asset. Polymorphic
-- input — see similar() for the (input, extras?) contract.
function AudioScape.sfxSimilar(
	self: AudioScapeInstance,
	input: AssetIdResolvable,
	extras: SfxSimilarExtras?
): (SfxSimilarResult?, string?)
	local assetId = resolveAssetId(input)
	if not assetId then
		return nil, "sfxSimilar requires an asset_id string, a track table, a Sound, or an AudioPlayer"
	end

	local opts: any = extras or (type(input) == "table" and input or {})

	-- GET so CloudFront edge-caches. dedupe=false is omitted (no point
	-- sending the no-op default — keeps the cache key clean).
	return requestGet(self, "/v1/sfx/similar", {
		asset_id = assetId,
		limit = opts.limit,
		offset = opts.offset,
		filters = opts.filters,
		max_score = opts.max_score,
		dedupe = if opts.dedupe == true then true else nil,
	}, opts.playerId)
end

function AudioScape.browse(
	self: AudioScapeInstance,
	options: BrowseOptions
): (BrowseListResult | BrowseTracksResult | nil, string?)
	if type(options.type) ~= "string" or not VALID_BROWSE_TYPES[options.type] then
		return nil, "browse requires type to be one of: artist, album, genre, mood, trending"
	end

	-- GET so CloudFront edge-caches.
	return requestGet(self, "/v1/browse", {
		type = options.type,
		name = options.name,
		limit = options.limit,
		offset = options.offset,
		sort = options.sort,
		region = options.region,
	}, options.playerId)
end

-- Browse sound effects. v1 only supports type='trending' — a global,
-- popularity-ranked list of SFX assets. Mirrors browse() but returns
-- SfxTrack-shaped entries with no list mode.
function AudioScape.sfxBrowse(self: AudioScapeInstance, options: SfxBrowseOptions): (SfxBrowseResult?, string?)
	if type(options.type) ~= "string" or not VALID_SFX_BROWSE_TYPES[options.type] then
		return nil, "sfxBrowse requires type to be one of: trending"
	end

	-- GET so CloudFront edge-caches.
	return requestGet(self, "/v1/sfx/browse", {
		type = options.type,
		name = options.name,
		limit = options.limit,
		offset = options.offset,
		region = options.region,
	}, options.playerId)
end

function AudioScape.getPlaylist(self: AudioScapeInstance, options: PlaylistOptions): (PlaylistResult?, string?)
	if type(options.playlist_id) ~= "string" or #options.playlist_id == 0 then
		return nil, "getPlaylist requires a non-empty playlist_id string"
	end

	local body: { [string]: any } = {
		playlist_id = options.playlist_id,
	}

	return request(self, "/v1/playlist", body, options.playerId)
end

function AudioScape.listPlaylists(self: AudioScapeInstance, playerId: number?): (ListPlaylistsResult?, string?)
	local body: { [string]: any } = {
		action = "list",
	}

	return request(self, "/v1/playlist", body, playerId)
end

--[[ ──────────────────────────────────────────
     Track Structure (beat grid + sections)
     ────────────────────────────────────────── ]]

-- Polymorphic input — see similar() for the (input, extras?) contract. Result
-- is cached per resolved asset_id, so passing the same Sound/Track/string
-- twice hits memory the second time.
function AudioScape.getStructure(
	self: AudioScapeInstance,
	input: AssetIdResolvable,
	extras: StructureExtras?
): (StructureResult?, string?)
	local assetId = resolveAssetId(input)
	if not assetId then
		return nil, "getStructure requires an asset_id string, a track table, a Sound, or an AudioPlayer"
	end

	local opts: any = extras or (type(input) == "table" and input or {})

	local cached = self._structureCache[assetId]
	if cached then
		return cached, nil
	end

	local result, err = request(self, "/v1/track/structure", { asset_id = assetId }, opts.playerId)
	if not result then
		return nil, err
	end

	self._structureCache[assetId] = result
	return result, nil
end

-- Locate the beat closest in time to `t` seconds. Uses binary search over the
-- sorted beat_times array. Returns nil if the asset has no beat_grid.
function AudioScape.beatAtTime(self: AudioScapeInstance, asset_id: string, t: number): (BeatHit?, string?)
	local structure, err = self:getStructure({ asset_id = asset_id })
	if not structure then
		return nil, err
	end
	local grid = structure.beat_grid
	if not grid or #grid.times == 0 then
		return nil, nil
	end

	local times = grid.times
	local lo, hi = 1, #times
	while lo < hi do
		local mid = (lo + hi) // 2
		if times[mid] < t then
			lo = mid + 1
		else
			hi = mid
		end
	end

	-- lo now points to the first beat >= t; pick whichever neighbor is closer.
	local idx = lo
	if idx > 1 and math.abs(times[idx - 1] - t) <= math.abs(times[idx] - t) then
		idx = idx - 1
	end

	local beatTime = times[idx]
	-- beat_num isn't returned to the SDK directly; reconstruct from the
	-- downbeats list (a beat is a downbeat iff its time appears in downbeats).
	local downbeatSet: { [number]: boolean } = {}
	for _, dt in ipairs(grid.downbeats) do
		downbeatSet[dt] = true
	end
	local isDownbeat = downbeatSet[beatTime] == true

	-- beat_num: count beats since the most recent downbeat (1..4)
	local beatNum = 1
	if not isDownbeat then
		for i = idx - 1, 1, -1 do
			if downbeatSet[times[i]] then
				beatNum = (idx - i) + 1
				break
			end
		end
	end

	return {
		index = idx,
		time = beatTime,
		beat_num = beatNum,
		is_downbeat = isDownbeat,
	}, nil
end

-- Find the section (or phrase) containing time `t`. `level` defaults to "section"
-- (the finer layer); pass "phrase" for the coarser groupings.
function AudioScape.sectionAtTime(
	self: AudioScapeInstance,
	asset_id: string,
	t: number,
	level: string?
): (Section?, string?)
	local structure, err = self:getStructure({ asset_id = asset_id })
	if not structure then
		return nil, err
	end

	local list = if level == "phrase" then structure.phrases else structure.sections
	for _, section in ipairs(list) do
		if t >= section.start and t < section["end"] then
			return section, nil
		end
	end

	return nil, nil
end

--[[ ──────────────────────────────────────────
     AssetService drop-in
     ────────────────────────────────────────── ]]

-- Maps AudioSearchParams -> our catalog and AudioPages -> our results, so an
-- existing `AssetService:SearchAudioAsync(params)` call site works unchanged
-- against AudioScape. Only SearchAudioAsync/SearchAudio are overridden;
-- everything else forwards to the real service (see getAssetService).

-- AudioSearchParams signals "unset" with sentinels rather than nil: strings
-- default to "", MinDuration to 0, MaxDuration to int32 max, AudioSubType to
-- Music. Verified against a live engine — treating MaxDuration's sentinel as a
-- real value would attach a meaningless duration ceiling to every request.
local AUDIO_SEARCH_MAX_DURATION_UNSET = 2147483647

-- Native SearchAudioAsync returns 30 results per page. Match it so paging
-- through the shim behaves the same as paging through the real thing.
local NATIVE_AUDIO_PAGE_SIZE = 30

export type AudioResult = {
	Id: number,
	Title: string,
	Artist: string,
	Description: string,
	Duration: number,
	Tags: { string },
	AudioType: string,
	IsEndorsed: boolean,
	CreateTime: string,
	UpdateTime: string,
	Creator: {
		Id: number,
		Name: string,
		Type: number,
		IsVerifiedCreator: boolean,
	},
	-- Additive AudioScape fields. Native has no equivalent, and adding keys
	-- can't break a consumer that only reads the native ones.
	AssetId: string,
	Score: number?,
	Genre: string?,
	GenreSlug: string?,
	Bpm: number?,
}

export type AudioScapeAudioPages = {
	IsFinished: boolean,
	GetCurrentPage: (self: AudioScapeAudioPages) -> { AudioResult },
	AdvanceToNextPageAsync: (self: AudioScapeAudioPages) -> (),
}

export type AssetServiceOptions = {
	-- When an AudioScape request fails, fall through to the real
	-- AssetService:SearchAudioAsync instead of erroring. On by default: the
	-- swap should never leave a caller worse off than native.
	fallback: boolean?,
	-- Results per page. Defaults to native's 30.
	limit: number?,
}

local function emptyToNil(value: any): string?
	if type(value) == "string" and #value > 0 then
		return value
	end
	return nil
end

-- Accepts a real AudioSearchParams Instance or a plain table with the same
-- field names — the client bridge sends the latter across a RemoteFunction,
-- where Instances can't be passed by reference.
local function paramsToOptions(params: any, limit: number, offset: number): ({ [string]: any }, boolean)
	local subType = params.AudioSubType
	local subTypeName = if typeof(subType) == "EnumItem" then subType.Name else tostring(subType)
	local isSfx = subTypeName == "SoundEffect"

	-- Neither endpoint has a title or album filter, and artist matching is
	-- already folded into /v1/search — so these join the query text rather
	-- than being silently dropped.
	local queryParts: { string } = {}
	for _, field in { "SearchKeyword", "Title", "Artist", "Album" } do
		local value = emptyToNil(params[field])
		if value then
			table.insert(queryParts, value)
		end
	end

	local tag = emptyToNil(params.Tag)
	-- A Tag-only search is legitimate on the native API. We can't run a
	-- semantic search with no text, so the tag doubles as the query.
	if #queryParts == 0 and tag then
		table.insert(queryParts, tag)
	end

	local minDuration = tonumber(params.MinDuration) or 0
	local maxDuration = tonumber(params.MaxDuration) or AUDIO_SEARCH_MAX_DURATION_UNSET
	local hasMin = minDuration > 0
	local hasMax = maxDuration > 0 and maxDuration < AUDIO_SEARCH_MAX_DURATION_UNSET

	local filters: { [string]: any }? = nil
	if hasMin or hasMax then
		filters = {
			duration = {
				min = if hasMin then minDuration else nil,
				max = if hasMax then maxDuration else nil,
			},
		}
	end
	if tag then
		local withTag: { [string]: any } = filters or {}
		if isSfx then
			withTag.categories = { tag }
		else
			withTag.genres = { tag }
		end
		filters = withTag
	end

	return {
		query = if #queryParts > 0 then table.concat(queryParts, " ") else nil,
		limit = limit,
		offset = offset,
		filters = filters,
	},
		isSfx
end

local function mapTrackToAudioResult(track: any): AudioResult
	local tags: { string } = {}
	if type(track.genre) == "string" and #track.genre > 0 then
		table.insert(tags, track.genre)
	end

	return {
		Id = tonumber(track.asset_id) or 0,
		Title = track.name or "",
		Artist = track.artist or "",
		Description = "",
		Duration = track.duration or 0,
		Tags = tags,
		-- Native returns AudioType as a plain string here. GetAudioMetadataAsync
		-- returns the EnumItem instead — the two engine APIs disagree, so match
		-- whichever one is being stood in for rather than normalising.
		AudioType = "Music",
		-- Roblox's own endorsement flag. We don't ingest it and won't invent a
		-- value, but native always returns the field, so omitting it would
		-- break strictly-typed consumers.
		IsEndorsed = false,
		CreateTime = track.created_at or "",
		UpdateTime = track.updated_at or "",
		Creator = {
			-- /v1/search returns creator_name for music but no creator_id.
			Id = tonumber(track.creator_id) or 0,
			Name = track.creator_name or "",
			Type = 1,
			IsVerifiedCreator = false,
		},
		AssetId = track.asset_id,
		Score = track.score,
		Genre = track.genre,
		GenreSlug = track.genre_slug,
		Bpm = track.bpm,
	}
end

local function mapSfxToAudioResult(track: any): AudioResult
	local tags: { string } = {}
	local seen: { [string]: boolean } = {}
	local function addTag(value: any)
		if type(value) == "string" then
			local trimmed = string.match(value, "^%s*(.-)%s*$")
			if trimmed and #trimmed > 0 and not seen[trimmed] then
				seen[trimmed] = true
				table.insert(tags, trimmed)
			end
		end
	end

	addTag(track.category)
	addTag(track.subcategory)
	-- SfxTrack.tags is a delimited string rather than an array. Split on commas
	-- and fall back to treating the whole value as a single tag.
	if type(track.tags) == "string" then
		for part in string.gmatch(track.tags, "[^,]+") do
			addTag(part)
		end
	end

	return {
		Id = tonumber(track.asset_id) or 0,
		Title = track.name or "",
		Artist = track.creator_name or "",
		Description = track.description or "",
		Duration = track.duration or 0,
		Tags = tags,
		AudioType = "SoundEffect",
		IsEndorsed = false,
		CreateTime = track.created_at or "",
		UpdateTime = track.updated_at or "",
		Creator = {
			Id = tonumber(track.creator_id) or 0,
			Name = track.creator_name or "",
			Type = 1,
			IsVerifiedCreator = false,
		},
		AssetId = track.asset_id,
		Score = track.score,
	}
end

-- Shared by the server shim and the client bridge: turns a raw search result
-- into the native page shape. Returns the mapped page plus the total, so the
-- caller can decide whether more pages remain.
local function mapSearchResultToPage(result: any, isSfx: boolean): ({ AudioResult }, number)
	local page: { AudioResult } = {}
	for _, track in (result.tracks or {}) do
		table.insert(page, if isSfx then mapSfxToAudioResult(track) else mapTrackToAudioResult(track))
	end
	local total = (result.meta and tonumber(result.meta.total)) or #page
	return page, total
end

-- Builds the AudioPages stand-in. `fetchPage(offset)` must return
-- (page, total) or raise — matching native, which throws rather than
-- returning an error value.
local function createAudioPages(
	fetchPage: (number) -> ({ AudioResult }, number),
	pageSize: number
): AudioScapeAudioPages
	local offset = 0
	local page, total = fetchPage(offset)

	local pages = {} :: any
	pages.IsFinished = #page == 0 or (offset + #page) >= total

	function pages.GetCurrentPage(): { AudioResult }
		return page
	end

	function pages.AdvanceToNextPageAsync()
		assert(not pages.IsFinished, "AudioPages: no more pages to advance to")
		offset += pageSize
		page, total = fetchPage(offset)
		pages.IsFinished = #page == 0 or (offset + #page) >= total
	end

	return pages :: AudioScapeAudioPages
end

-- Drop-in stand-in for game:GetService("AssetService").
--
--   local AssetService = AudioScape:getAssetService()
--   local params = Instance.new("AudioSearchParams")
--   params.SearchKeyword = "chill lofi"
--   local pages = AssetService:SearchAudioAsync(params)
--
-- SearchAudioAsync runs against AudioScape's semantic catalog; AudioSubType
-- routes to the music or SFX index. Every other member forwards to the real
-- AssetService, so swapping the service in leaves unrelated calls untouched.
function AudioScape.getAssetService(self: AudioScapeInstance, options: AssetServiceOptions?)
	local opts: AssetServiceOptions = options or {}
	local useFallback = opts.fallback ~= false
	local pageSize = opts.limit or NATIVE_AUDIO_PAGE_SIZE

	local shim = {} :: any

	function shim.SearchAudioAsync(_, params: any): AudioScapeAudioPages
		local isInstance = typeof(params) == "Instance"
		assert(isInstance or type(params) == "table", "SearchAudioAsync requires an AudioSearchParams")

		local function nativePages(): AudioScapeAudioPages?
			if not (useFallback and isInstance) then
				return nil
			end
			local ok, result = pcall(function()
				return game:GetService("AssetService"):SearchAudioAsync(params)
			end)
			if ok then
				return result :: any
			end
			return nil
		end

		local lastError: string? = nil
		local function fetchPage(offset: number): ({ AudioResult }, number)
			local searchOptions, isSfx = paramsToOptions(params, pageSize, offset)
			if not searchOptions.query then
				lastError = "SearchAudioAsync requires SearchKeyword, Title, Artist, Album, or Tag to be set"
				error(lastError, 0)
			end

			local result: any, err: string?
			if isSfx then
				result, err = AudioScape.sfxSearch(self, searchOptions :: any)
			else
				result, err = AudioScape.search(self, searchOptions :: any)
			end
			if not result then
				lastError = err or "search failed"
				error(lastError, 0)
			end

			local page, total = mapSearchResultToPage(result, isSfx)
			AudioScape.trackCustom(self, "search_shim", nil, nil, {
				query = string.sub(searchOptions.query :: string, 1, 256),
				sub_type = if isSfx then "SoundEffect" else "Music",
				result_count = #page,
				offset = offset,
			})
			return page, total
		end

		local ok, pages = pcall(createAudioPages, fetchPage, pageSize)
		if ok then
			return pages
		end

		local native = nativePages()
		if native then
			AudioScape.trackCustom(self, "search_fallback", nil, nil, {
				reason = string.sub(tostring(lastError or pages), 1, 256),
			})
			return native
		end

		error(tostring(lastError or pages), 0)
	end

	-- Deprecated engine alias, still used by plenty of existing code.
	shim.SearchAudio = shim.SearchAudioAsync

	-- Forward anything we don't override — CreateEditableImage,
	-- GetAudioMetadataAsync, GetBundleDetailsAsync and friends — so this is a
	-- complete stand-in rather than a two-method object. Passing
	-- GetAudioMetadataAsync straight through also means callers keep the fields
	-- the engine returns that we don't hold.
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

--[[ ──────────────────────────────────────────
     Audio audit
     ────────────────────────────────────────── ]]

-- /v1/search caps an asset_ids lookup at 100.
local LOOKUP_BATCH_SIZE = 100

-- Where audio normally lives. Scanning `game` outright would walk services
-- that never hold Sounds and can be enormous.
local DEFAULT_AUDIT_ROOTS = {
	"Workspace",
	"ReplicatedStorage",
	"ServerStorage",
	"ServerScriptService",
	"StarterGui",
	"StarterPack",
	"StarterPlayer",
	"SoundService",
	"Lighting",
}

export type AudioAuditOptions = {
	-- Containers to walk. Defaults to the services above. Pass a narrower
	-- list on a large place — GetDescendants on a big Workspace is not free.
	roots: { Instance }?,
	playerId: number?,
}

export type AudioAssetUsage = {
	asset_id: string,
	-- How many Sound / AudioPlayer instances reference this asset.
	uses: number,
	-- Full name of the first instance found, so you can jump straight to it.
	sample_path: string,
	-- Whether AudioScape's catalog has this asset. `false` means we can't
	-- offer variations or similarity for it — it may still play fine.
	known: boolean,
}

export type AudioAuditResult = {
	assets: { AudioAssetUsage },
	meta: {
		instances_scanned: number,
		distinct_assets: number,
		known: number,
		unknown: number,
	},
}

-- Inventory every audio asset referenced in the place, and check which ones
-- AudioScape's catalog knows about.
--
--   local audit = AudioScape:auditAudio()
--   print(audit.meta.distinct_assets .. " distinct assets in this place")
--
-- Read-only and safe to call at any time, but it walks the data model, so
-- treat it as a startup or development diagnostic rather than something to
-- poll. `known = false` only means the asset isn't in our catalog — it says
-- nothing about whether the asset still plays.
function AudioScape.auditAudio(self: AudioScapeInstance, options: AudioAuditOptions?): (AudioAuditResult?, string?)
	local opts: AudioAuditOptions = options or {}

	local roots: { Instance } = opts.roots or {}
	if #roots == 0 then
		for _, name in DEFAULT_AUDIT_ROOTS do
			-- Some services aren't reachable from every context (and
			-- GetService throws on an unknown name), so skip rather than fail
			-- the whole audit.
			local ok, service = pcall(function()
				return game:GetService(name :: any)
			end)
			if ok and service then
				table.insert(roots, service)
			end
		end
	end

	local usage: { [string]: AudioAssetUsage } = {}
	local order: { string } = {}
	local scanned = 0

	for _, root in roots do
		local ok, descendants = pcall(function()
			return root:GetDescendants()
		end)
		if not ok then
			continue
		end
		for _, instance in descendants do
			if not (instance:IsA("Sound") or instance:IsA("AudioPlayer")) then
				continue
			end
			scanned += 1
			local assetId = resolveAssetId(instance)
			if not assetId then
				-- An empty SoundId is normal for a template Sound that gets
				-- its asset assigned at runtime; nothing to report.
				continue
			end
			local entry = usage[assetId]
			if entry then
				entry.uses += 1
			else
				usage[assetId] = {
					asset_id = assetId,
					uses = 1,
					sample_path = instance:GetFullName(),
					known = false,
				}
				table.insert(order, assetId)
			end
		end
	end

	-- Resolve in batches. A partial failure fails the whole audit rather than
	-- silently reporting assets as unknown when we simply couldn't ask.
	local knownCount = 0
	for start = 1, #order, LOOKUP_BATCH_SIZE do
		local batch: { string } = {}
		for i = start, math.min(start + LOOKUP_BATCH_SIZE - 1, #order) do
			table.insert(batch, order[i])
		end

		local result, err = AudioScape.lookup(self, { asset_ids = batch, playerId = opts.playerId })
		if not result then
			return nil, err
		end
		local tracks: { Track } = result.tracks or {}
		for _, track in tracks do
			local entry = usage[tostring(track.asset_id)]
			if entry and not entry.known then
				entry.known = true
				knownCount += 1
			end
		end
	end

	local assets: { AudioAssetUsage } = {}
	for _, assetId in order do
		table.insert(assets, usage[assetId])
	end
	-- Most-used first: that's the order you'd want to act on them in.
	table.sort(assets, function(a, b)
		if a.uses == b.uses then
			return a.asset_id < b.asset_id
		end
		return a.uses > b.uses
	end)

	return {
		assets = assets,
		meta = {
			instances_scanned = scanned,
			distinct_assets = #order,
			known = knownCount,
			unknown = #order - knownCount,
		},
	},
		nil
end

--[[ ──────────────────────────────────────────
     Music Player
     ────────────────────────────────────────── ]]

export type PlayerOptions = AudioScapeMusicPlayer.PlayerOptions

-- Create an AudioScapeMusicPlayer that manages audio playback and auto-tracks analytics.
-- AudioScapeClient structurally satisfies AudioScapeMusicPlayer's AnalyticsClient
-- duck-type (trackPlay/trackStop/trackSkip), but the analyzer can't see the
-- structural match across modules — cast to any here, exercised by the player tests.
function AudioScape.createPlayer(
	self: AudioScapeInstance,
	options: PlayerOptions?
): AudioScapeMusicPlayer.MusicPlayerInstance
	return AudioScapeMusicPlayer.new(self :: any, options)
end

--[[ ──────────────────────────────────────────
     Client Access
     ────────────────────────────────────────── ]]

local RATE_LIMIT_INTERVAL = 1 -- minimum seconds between requests per player
local playerLastRequest: { [number]: number } = {}

local function checkRateLimit(player: Player): boolean
	local now = workspace:GetServerTimeNow()
	local last = playerLastRequest[player.UserId]
	if last and (now - last) < RATE_LIMIT_INTERVAL then
		return false
	end
	playerLastRequest[player.UserId] = now
	return true
end

-- Enable client-side access via RemoteFunctions.
-- Creates AudioScapeRemotes in ReplicatedStorage. Use with AudioScapeClient module in LocalScripts.
function AudioScape.enableClientAccess(self: AudioScapeInstance)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Players = game:GetService("Players")

	local folder = Instance.new("Folder")
	folder.Name = "AudioScapeRemotes"

	local function createRemote(name: string, handler: (player: Player, ...any) -> ...any)
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.OnServerInvoke = handler
		remote.Parent = folder
	end

	createRemote("Search", function(player: Player, options: any)
		if not checkRateLimit(player) then
			return nil, "Rate limited — please wait before making another request"
		end
		if type(options) ~= "table" then
			return nil, "search requires a table with a query string or an asset_ids array"
		end
		local hasQuery = type(options.query) == "string" and #options.query > 0
		local hasIds = type(options.asset_ids) == "table" and #options.asset_ids > 0
		if not hasQuery and not hasIds then
			return nil, "search requires a query string or a non-empty asset_ids array"
		end
		return self:search({
			query = options.query,
			asset_ids = options.asset_ids,
			limit = options.limit,
			offset = options.offset,
			filters = options.filters,
			region = options.region,
			sort = options.sort,
			playerId = player.UserId,
		})
	end)

	-- Backs AudioScapeClient:getAssetService(). The client can't hand an
	-- AudioSearchParams Instance across a RemoteFunction, so it sends the
	-- property values as a table and receives an already-mapped page — that
	-- keeps the result mapping in one place instead of duplicating it client-side.
	createRemote("SearchAudio", function(player: Player, params: any, offset: any, limit: any)
		if not checkRateLimit(player) then
			return nil, "Rate limited — please wait before making another request"
		end
		if type(params) ~= "table" then
			return nil, "searchAudio requires an AudioSearchParams-shaped table"
		end

		local pageSize = math.clamp(tonumber(limit) or NATIVE_AUDIO_PAGE_SIZE, 1, 100)
		local pageOffset = math.max(tonumber(offset) or 0, 0)
		local searchOptions, isSfx = paramsToOptions(params, pageSize, pageOffset)
		if not searchOptions.query then
			return nil, "SearchAudioAsync requires SearchKeyword, Title, Artist, Album, or Tag to be set"
		end
		searchOptions.playerId = player.UserId

		local result: any, err: string?
		if isSfx then
			result, err = self:sfxSearch(searchOptions :: any)
		else
			result, err = self:search(searchOptions :: any)
		end
		if not result then
			return nil, err
		end

		local page, total = mapSearchResultToPage(result, isSfx)
		return { page = page, total = total }
	end)

	createRemote("Similar", function(player: Player, options: any)
		if not checkRateLimit(player) then
			return nil, "Rate limited — please wait before making another request"
		end
		if type(options) ~= "table" or type(options.asset_id) ~= "string" then
			return nil, "similar requires a table with an asset_id string"
		end
		return self:similar({
			asset_id = options.asset_id,
			limit = options.limit,
			offset = options.offset,
			filters = options.filters,
			playerId = player.UserId,
		})
	end)

	createRemote("SfxSearch", function(player: Player, options: any)
		if not checkRateLimit(player) then
			return nil, "Rate limited — please wait before making another request"
		end
		if type(options) ~= "table" then
			return nil, "sfxSearch requires a table"
		end
		local hasQuery = type(options.query) == "string" and #options.query > 0
		local hasCategory = type(options.filters) == "table"
			and type(options.filters.categories) == "table"
			and #options.filters.categories > 0
		if not hasQuery and not hasCategory then
			return nil, "sfxSearch requires either a query string or filters.categories"
		end
		return self:sfxSearch({
			query = options.query,
			limit = options.limit,
			offset = options.offset,
			sort = options.sort,
			filters = options.filters,
			playerId = player.UserId,
		})
	end)

	createRemote("GetSfxTaxonomy", function(player: Player)
		if not checkRateLimit(player) then
			return nil, "Rate limited — please wait before making another request"
		end
		return self:getSfxTaxonomy()
	end)

	createRemote("SfxSimilar", function(player: Player, options: any)
		if not checkRateLimit(player) then
			return nil, "Rate limited — please wait before making another request"
		end
		if type(options) ~= "table" or type(options.asset_id) ~= "string" then
			return nil, "sfxSimilar requires a table with an asset_id string"
		end
		return self:sfxSimilar({
			asset_id = options.asset_id,
			limit = options.limit,
			offset = options.offset,
			filters = options.filters,
			playerId = player.UserId,
		})
	end)

	createRemote("Browse", function(player: Player, options: any)
		if not checkRateLimit(player) then
			return nil, "Rate limited — please wait before making another request"
		end
		if type(options) ~= "table" or type(options.type) ~= "string" then
			return nil, "browse requires a table with a type string"
		end
		return self:browse({
			type = options.type,
			name = options.name,
			limit = options.limit,
			offset = options.offset,
			sort = options.sort,
			region = options.region,
			playerId = player.UserId,
		})
	end)

	createRemote("SfxBrowse", function(player: Player, options: any)
		if not checkRateLimit(player) then
			return nil, "Rate limited — please wait before making another request"
		end
		if type(options) ~= "table" or type(options.type) ~= "string" then
			return nil, "sfxBrowse requires a table with a type string"
		end
		return self:sfxBrowse({
			type = options.type,
			name = options.name,
			limit = options.limit,
			offset = options.offset,
			region = options.region,
			playerId = player.UserId,
		})
	end)

	createRemote("GetPlaylist", function(player: Player, options: any)
		if not checkRateLimit(player) then
			return nil, "Rate limited — please wait before making another request"
		end
		if type(options) ~= "table" or type(options.playlist_id) ~= "string" then
			return nil, "getPlaylist requires a table with a playlist_id string"
		end
		return self:getPlaylist({
			playlist_id = options.playlist_id,
			playerId = player.UserId,
		})
	end)

	createRemote("ListPlaylists", function(player: Player)
		if not checkRateLimit(player) then
			return nil, "Rate limited — please wait before making another request"
		end
		return self:listPlaylists(player.UserId)
	end)

	createRemote("GetStructure", function(player: Player, options: any)
		if not checkRateLimit(player) then
			return nil, "Rate limited — please wait before making another request"
		end
		if type(options) ~= "table" or type(options.asset_id) ~= "string" then
			return nil, "getStructure requires a table with an asset_id string"
		end
		return self:getStructure({
			asset_id = options.asset_id,
			playerId = player.UserId,
		})
	end)

	-- Clean up rate limit entries when players leave
	Players.PlayerRemoving:Connect(function(player: Player)
		playerLastRequest[player.UserId] = nil
	end)

	folder.Parent = ReplicatedStorage
end

-- Test-only export. Gated on _G.__AUDIOSCAPE_TEST so production callers
-- never see __internal. The Lune harness sets the flag before requiring
-- the module so its specs can reach pure helpers without spinning the
-- full client.
-- selene: allow(global_usage)
if _G.__AUDIOSCAPE_TEST then
	-- selene: allow(global_usage)
	(AudioScape :: any).__internal = {
		computeAnalyticsBackoff = computeAnalyticsBackoff,
		formatError = formatError,
		buildQuery = buildQuery,
		resolveAssetId = resolveAssetId,
		paramsToOptions = paramsToOptions,
		mapTrackToAudioResult = mapTrackToAudioResult,
		mapSfxToAudioResult = mapSfxToAudioResult,
		mapSearchResultToPage = mapSearchResultToPage,
		createAudioPages = createAudioPages,
	}
end

return AudioScape
