--!strict

local HttpService = game:GetService("HttpService")

local BASE_URL = "https://api.audioscape.ai/developer"

local VALID_BROWSE_TYPES = {
	artist = true,
	album = true,
	genre = true,
	mood = true,
}

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
	}?,
}

export type SimilarOptions = {
	asset_id: string,
	limit: number?,
	offset: number?,
	playerId: number?,
}

export type BrowseOptions = {
	type: string,
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
		name: string,
	},
}

local AudioScape = {}
AudioScape.__index = AudioScape

type AudioScapeClient = typeof(setmetatable({} :: {
	_apiKey: any,
	_universeId: string,
	_placeId: string,
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

function AudioScape.new(apiKey: any): AudioScapeClient
	assert(apiKey ~= nil, "AudioScape.new requires an API key (string or Secret)")
	if type(apiKey) == "string" then
		assert(#apiKey > 0, "AudioScape.new requires a non-empty API key string")
	end

	local self = setmetatable({
		_apiKey = apiKey,
		_universeId = tostring(game.GameId),
		_placeId = tostring(game.PlaceId),
	}, AudioScape)

	return self
end

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
	}

	return request(self, "/v1/similar", body, options.playerId)
end

function AudioScape.browse(self: AudioScapeClient, options: BrowseOptions): (BrowseListResult | BrowseTracksResult | nil, string?)
	if type(options.type) ~= "string" or not VALID_BROWSE_TYPES[options.type] then
		return nil, "browse requires type to be one of: artist, album, genre, mood"
	end

	local body: { [string]: any } = {
		type = options.type,
		name = options.name,
		limit = options.limit,
		offset = options.offset,
	}

	return request(self, "/v1/browse", body, options.playerId)
end

return AudioScape
