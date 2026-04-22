--!strict

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local AudioScapeMusicPlayer = require(script.AudioScapeMusicPlayer)

local BASE_URL = "https://api.audioscape.ai/developer"
local ANALYTICS_URL = "https://api.audioscape.ai/analytics"

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
	query: string,
	limit: number?,
	offset: number?,
	playerId: number?,
	filters: {
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

export type BrowseOptions = {
	type: string, -- "artist" | "album" | "genre" | "mood" | "trending"
	name: string?,
	limit: number?,
	offset: number?,
	playerId: number?,
}

export type SfxBrowseOptions = {
	type: string, -- "trending"
	name: string?,
	limit: number?,
	offset: number?,
	playerId: number?,
}

export type Track = {
	asset_id: string,
	name: string,
	artist: string,
	album: string,
	genre: string,
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
		search_method: string,
		matched_artist: string?,
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
	end: number,
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
	genre: string,
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

local AudioScape = {}
AudioScape.__index = AudioScape

type AudioScapeClient = typeof(setmetatable({} :: {
	_apiKey: any,
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
}, AudioScape))

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

local function request(self: AudioScapeClient, path: string, body: { [string]: any }, playerId: number?): (any, string?)
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
		Url = BASE_URL .. path,
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
local function buildQuery(params: { [string]: any }): string
	local parts: { string } = {}
	for key, value in pairs(params) do
		if value ~= nil then
			table.insert(parts, key .. "=" .. HttpService:UrlEncode(tostring(value)))
		end
	end
	if #parts == 0 then
		return ""
	end
	return "?" .. table.concat(parts, "&")
end

-- v0.10.0: GET sibling of request() for endpoints CloudFront edge-caches
-- (browse, sfxBrowse, sfxTaxonomy). API still accepts the equivalent POST
-- for older SDK clients; flagged as a v1.0.0 cleanup candidate to fold both
-- into one method-aware helper.
local function requestGet(self: AudioScapeClient, path: string, query: { [string]: any }, playerId: number?): (any, string?)
	local headers: { [string]: any } = {
		["x-api-key"] = self._apiKey,
		["X-Universe-Id"] = self._universeId,
		["X-Place-Id"] = self._placeId,
	}
	if playerId then
		headers["X-Player-Id"] = tostring(playerId)
	end

	local ok, result = pcall(HttpService.RequestAsync, HttpService, {
		Url = BASE_URL .. path .. buildQuery(query),
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

local function requeueBatch(self: AudioScapeClient, batch: { AnalyticsEvent })
	for i = #batch, 1, -1 do
		table.insert(self._analyticsBuffer, 1, batch[i])
	end
	-- Trim to maxQueueSize (drop newest un-sent events from the tail)
	while #self._analyticsBuffer > self._analyticsMaxQueueSize do
		table.remove(self._analyticsBuffer)
	end
end

local function flushAnalyticsBuffer(self: AudioScapeClient): boolean
	if #self._analyticsBuffer == 0 then
		return true
	end

	-- Drain up to maxBatchSize events from the buffer
	local batch: { AnalyticsEvent } = {}
	local count = math.min(#self._analyticsBuffer, self._analyticsMaxBatchSize)
	for _ = 1, count do
		table.insert(batch, table.remove(self._analyticsBuffer, 1))
	end

	local jsonBody = HttpService:JSONEncode({ events = batch })

	local headers: { [string]: any } = {
		["x-api-key"] = self._apiKey,
		["Content-Type"] = "application/json",
		["X-Universe-Id"] = self._universeId,
		["X-Place-Id"] = self._placeId,
	}

	local ok, result = pcall(HttpService.RequestAsync, HttpService, {
		Url = ANALYTICS_URL .. "/v1/analytics",
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

local function startAnalyticsLoop(self: AudioScapeClient)
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
					self._analyticsBackoff = self._analyticsBatchInterval
					self._analyticsConsecutiveFailures = 0
				else
					self._analyticsConsecutiveFailures += 1
					self._analyticsBackoff = math.min(
						self._analyticsBatchInterval * (2 ^ self._analyticsConsecutiveFailures),
						300
					)
				end
			end
		end
	end)
end

local function enqueueEvent(self: AudioScapeClient, event: AnalyticsEvent)
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

function AudioScape.new(apiKey: any): AudioScapeClient
	assert(apiKey ~= nil, "AudioScape.new requires an API key (string or Secret)")
	if type(apiKey) == "string" then
		assert(#apiKey > 0, "AudioScape.new requires a non-empty API key string")
	end

	local self = setmetatable({
		_apiKey = apiKey,
		_universeId = tostring(game.GameId),
		_placeId = tostring(game.PlaceId),
		-- Analytics state
		_analyticsEnabled = true,
		_analyticsBatchInterval = DEFAULT_BATCH_INTERVAL,
		_analyticsMaxBatchSize = DEFAULT_MAX_BATCH_SIZE,
		_analyticsMaxQueueSize = DEFAULT_MAX_QUEUE_SIZE,
		_analyticsBuffer = {},
		_analyticsRunning = false,
		_analyticsBackoff = DEFAULT_BATCH_INTERVAL,
		_analyticsConsecutiveFailures = 0,
		_structureCache = {},
	}, AudioScape)

	-- Start analytics loop on server only
	if RunService:IsServer() and RunService:IsRunning() then
		startAnalyticsLoop(self)
	end

	return self
end

-- Configure analytics settings (call before tracking events)
function AudioScape.configureAnalytics(self: AudioScapeClient, config: AnalyticsConfig)
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
function AudioScape.flushAnalytics(self: AudioScapeClient)
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
function AudioScape.trackPlay(self: AudioScapeClient, assetId: string, playerId: (number | string)?, duration: number?)
	enqueueEvent(self, {
		type = "play",
		asset_id = assetId,
		player_id = if playerId then tostring(playerId) else nil,
		duration = duration,
	})
end

-- Track a song stop event (natural end or user action)
function AudioScape.trackStop(self: AudioScapeClient, assetId: string, playerId: (number | string)?, duration: number?)
	enqueueEvent(self, {
		type = "stop",
		asset_id = assetId,
		player_id = if playerId then tostring(playerId) else nil,
		duration = duration,
	})
end

-- Track a song skip event
function AudioScape.trackSkip(self: AudioScapeClient, assetId: string, playerId: (number | string)?, duration: number?)
	enqueueEvent(self, {
		type = "skip",
		asset_id = assetId,
		player_id = if playerId then tostring(playerId) else nil,
		duration = duration,
	})
end

-- Track a vote event (value must be "up" or "down")
function AudioScape.trackVote(self: AudioScapeClient, assetId: string, value: string, playerId: (number | string)?)
	assert(value == "up" or value == "down", "vote value must be 'up' or 'down'")
	enqueueEvent(self, {
		type = "vote",
		asset_id = assetId,
		value = value,
		player_id = if playerId then tostring(playerId) else nil,
	})
end

-- Track a favorite event
function AudioScape.trackFavorite(self: AudioScapeClient, assetId: string, playerId: (number | string)?)
	enqueueEvent(self, {
		type = "favorite",
		asset_id = assetId,
		player_id = if playerId then tostring(playerId) else nil,
	})
end

-- Track an unfavorite event
function AudioScape.trackUnfavorite(self: AudioScapeClient, assetId: string, playerId: (number | string)?)
	enqueueEvent(self, {
		type = "unfavorite",
		asset_id = assetId,
		player_id = if playerId then tostring(playerId) else nil,
	})
end

-- Track an add-to-queue event (setlist, playlist, etc.)
function AudioScape.trackAddToQueue(self: AudioScapeClient, assetId: string, playerId: (number | string)?)
	enqueueEvent(self, {
		type = "add_to_queue",
		asset_id = assetId,
		player_id = if playerId then tostring(playerId) else nil,
	})
end

-- Track a search result click
function AudioScape.trackSearchClick(self: AudioScapeClient, assetId: string, playerId: (number | string)?, metadata: { [string]: any }?)
	enqueueEvent(self, {
		type = "search_click",
		asset_id = assetId,
		player_id = if playerId then tostring(playerId) else nil,
		metadata = metadata,
	})
end

-- Track a custom event (any string type, flexible schema)
function AudioScape.trackCustom(self: AudioScapeClient, eventType: string, assetId: string?, playerId: (number | string)?, metadata: { [string]: any }?)
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

function AudioScape.search(self: AudioScapeClient, options: SearchOptions): (SearchResult?, string?)
	if type(options.query) ~= "string" or #options.query == 0 then
		return nil, "search requires a non-empty query string"
	end

	local body: { [string]: any } = {
		query = options.query,
		limit = options.limit,
		offset = options.offset,
		filters = options.filters,
	}

	return request(self, "/v1/search", body, options.playerId)
end

function AudioScape.similar(self: AudioScapeClient, options: SimilarOptions): (SimilarResult?, string?)
	if type(options.asset_id) ~= "string" or #options.asset_id == 0 then
		return nil, "similar requires a non-empty asset_id string"
	end

	local body: { [string]: any } = {
		asset_id = options.asset_id,
		limit = options.limit,
		offset = options.offset,
		filters = options.filters,
	}

	return request(self, "/v1/similar", body, options.playerId)
end

-- Search the SFX catalog. Pass `query` for free-text search, or pass
-- `filters.categories` (with optional `filters.subcategories`) to browse a
-- category — the API auto-injects a curated query so you get good results
-- without needing to know the right search terms.
function AudioScape.sfxSearch(self: AudioScapeClient, options: SfxSearchOptions): (SfxSearchResult?, string?)
	local hasQuery = type(options.query) == "string" and #options.query > 0
	local hasCategory = options.filters
		and type(options.filters.categories) == "table"
		and #options.filters.categories > 0
	if not hasQuery and not hasCategory then
		return nil, "sfxSearch requires either a query string or filters.categories"
	end

	local body: { [string]: any } = {
		query = options.query,
		limit = options.limit,
		offset = options.offset,
		filters = options.filters,
	}

	return request(self, "/v1/sfx/search", body, options.playerId)
end

-- Fetch the SFX taxonomy hierarchy (broader_category → category → subcategory)
-- so you can build pill UIs that mirror filters.categories / .subcategories on
-- /v1/sfx/search. The API caches the response for 10 minutes.
function AudioScape.getSfxTaxonomy(self: AudioScapeClient): (SfxTaxonomyResult?, string?)
	return requestGet(self, "/v1/sfx/taxonomy", {}, nil)
end

-- Find sound effects acoustically similar to a given asset.
function AudioScape.sfxSimilar(self: AudioScapeClient, options: SfxSimilarOptions): (SfxSimilarResult?, string?)
	if type(options.asset_id) ~= "string" or #options.asset_id == 0 then
		return nil, "sfxSimilar requires a non-empty asset_id string"
	end

	local body: { [string]: any } = {
		asset_id = options.asset_id,
		limit = options.limit,
		offset = options.offset,
		filters = options.filters,
	}

	return request(self, "/v1/sfx/similar", body, options.playerId)
end

function AudioScape.browse(self: AudioScapeClient, options: BrowseOptions): (BrowseListResult | BrowseTracksResult | nil, string?)
	if type(options.type) ~= "string" or not VALID_BROWSE_TYPES[options.type] then
		return nil, "browse requires type to be one of: artist, album, genre, mood, trending"
	end

	-- v0.10.0: GET so CloudFront edge-caches. POST endpoint still works on
	-- the API for older SDK clients.
	return requestGet(self, "/v1/browse", {
		type = options.type,
		name = options.name,
		limit = options.limit,
		offset = options.offset,
	}, options.playerId)
end

-- Browse sound effects. v1 only supports type='trending' — a global,
-- popularity-ranked list of SFX assets. Mirrors browse() but returns
-- SfxTrack-shaped entries with no list mode.
function AudioScape.sfxBrowse(self: AudioScapeClient, options: SfxBrowseOptions): (SfxBrowseResult?, string?)
	if type(options.type) ~= "string" or not VALID_SFX_BROWSE_TYPES[options.type] then
		return nil, "sfxBrowse requires type to be one of: trending"
	end

	-- v0.10.0: GET so CloudFront edge-caches. POST endpoint still works on
	-- the API for older SDK clients.
	return requestGet(self, "/v1/sfx/browse", {
		type = options.type,
		name = options.name,
		limit = options.limit,
		offset = options.offset,
	}, options.playerId)
end

function AudioScape.getPlaylist(self: AudioScapeClient, options: PlaylistOptions): (PlaylistResult?, string?)
	if type(options.playlist_id) ~= "string" or #options.playlist_id == 0 then
		return nil, "getPlaylist requires a non-empty playlist_id string"
	end

	local body: { [string]: any } = {
		playlist_id = options.playlist_id,
	}

	return request(self, "/v1/playlist", body, options.playerId)
end

function AudioScape.listPlaylists(self: AudioScapeClient, playerId: number?): (ListPlaylistsResult?, string?)
	local body: { [string]: any } = {
		action = "list",
	}

	return request(self, "/v1/playlist", body, playerId)
end

--[[ ──────────────────────────────────────────
     Track Structure (beat grid + sections)
     ────────────────────────────────────────── ]]

function AudioScape.getStructure(self: AudioScapeClient, options: StructureOptions): (StructureResult?, string?)
	if type(options.asset_id) ~= "string" or #options.asset_id == 0 then
		return nil, "getStructure requires a non-empty asset_id string"
	end

	local cached = self._structureCache[options.asset_id]
	if cached then
		return cached, nil
	end

	local result, err = request(self, "/v1/track/structure", { asset_id = options.asset_id }, options.playerId)
	if not result then
		return nil, err
	end

	self._structureCache[options.asset_id] = result
	return result, nil
end

-- Locate the beat closest in time to `t` seconds. Uses binary search over the
-- sorted beat_times array. Returns nil if the asset has no beat_grid.
function AudioScape.beatAtTime(self: AudioScapeClient, asset_id: string, t: number): (BeatHit?, string?)
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

-- Find the section (or phrase) containing time `t`. `level` defaults to "section".
function AudioScape.sectionAtTime(self: AudioScapeClient, asset_id: string, t: number, level: string?): (Section?, string?)
	local structure, err = self:getStructure({ asset_id = asset_id })
	if not structure then
		return nil, err
	end

	local list = if level == "phrase" then structure.phrases else structure.sections
	for _, section in ipairs(list) do
		if t >= section.start and t < section.end then
			return section, nil
		end
	end

	return nil, nil
end

--[[ ──────────────────────────────────────────
     Music Player
     ────────────────────────────────────────── ]]

export type PlayerOptions = AudioScapeMusicPlayer.PlayerOptions

-- Create an AudioScapeMusicPlayer that manages audio playback and auto-tracks analytics.
function AudioScape.createPlayer(self: AudioScapeClient, options: PlayerOptions?): AudioScapeMusicPlayer.MusicPlayerInstance
	return AudioScapeMusicPlayer.new(self, options)
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
function AudioScape.enableClientAccess(self: AudioScapeClient)
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
		if type(options) ~= "table" or type(options.query) ~= "string" then
			return nil, "search requires a table with a query string"
		end
		return self:search({
			query = options.query,
			limit = options.limit,
			offset = options.offset,
			filters = options.filters,
			playerId = player.UserId,
		})
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

return AudioScape
