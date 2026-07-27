--!strict
-- Unit tests for the AssetService drop-in (client:getAssetService()).
--
-- The sentinel handling below is the load-bearing part: AudioSearchParams
-- signals "unset" with "" / 0 / int32-max rather than nil, verified against a
-- live engine. Treating MaxDuration's sentinel as a real value would attach a
-- meaningless duration ceiling to every request.

local serde = require("@lune/serde")
local mockHttp = require("./_harness/mockHttp")
local loadSdk = require("./_harness/loadSdk").loadSdk

local MAX_DURATION_UNSET = 2147483647

-- A plain table with AudioSearchParams' field names. paramsToOptions accepts
-- this shape directly — it's what the client bridge sends across the
-- RemoteFunction, since an Instance can't cross by reference.
local function params(overrides: { [string]: any }?): { [string]: any }
	local p: { [string]: any } = {
		SearchKeyword = "",
		Title = "",
		Artist = "",
		Album = "",
		Tag = "",
		MinDuration = 0,
		MaxDuration = MAX_DURATION_UNSET,
		AudioSubType = "Music",
	}
	local extra: { [string]: any } = overrides or {}
	for k, v in extra do
		p[k] = v
	end
	return p
end

local function searchResponse(tracks: { any }, total: number?): mockHttp.Response
	return {
		Success = true,
		StatusCode = 200,
		Body = serde.encode("json", {
			tracks = tracks,
			artists = {},
			albums = {},
			meta = { total = total or #tracks, limit = 30, offset = 0, search_method = "semantic" },
		}),
	}
end

local function newSdk(): (any, any)
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	return sdk, http
end

local sdk = (newSdk())
local internal = (sdk :: any).__internal
local paramsToOptions = internal.paramsToOptions
local mapTrackToAudioResult = internal.mapTrackToAudioResult
local mapSfxToAudioResult = internal.mapSfxToAudioResult
local mapSearchResultToPage = internal.mapSearchResultToPage
local createAudioPages = internal.createAudioPages

-- 1. Unset sentinels produce no filters at all
do
	local opts, isSfx = paramsToOptions(params({ SearchKeyword = "chill lofi" }), 30, 0)
	assert(opts.query == "chill lofi", "query from SearchKeyword; got: " .. tostring(opts.query))
	assert(opts.filters == nil, "no filters when every param is at its unset sentinel")
	assert(isSfx == false, "AudioSubType Music routes to the music catalog")
	assert(opts.limit == 30 and opts.offset == 0, "limit/offset threaded through")
end

-- 2. MaxDuration's int32-max sentinel must never reach the API
do
	local opts = paramsToOptions(params({ SearchKeyword = "x", MaxDuration = MAX_DURATION_UNSET }), 30, 0)
	assert(opts.filters == nil, "int32-max MaxDuration is treated as unset, not as a real ceiling")

	local withMax = paramsToOptions(params({ SearchKeyword = "x", MaxDuration = 60 }), 30, 0)
	assert(withMax.filters.duration.max == 60, "a real MaxDuration is forwarded")
	assert(withMax.filters.duration.min == nil, "MinDuration 0 stays unset")

	local withMin = paramsToOptions(params({ SearchKeyword = "x", MinDuration = 30 }), 30, 0)
	assert(withMin.filters.duration.min == 30, "a real MinDuration is forwarded")
	assert(withMin.filters.duration.max == nil, "MaxDuration sentinel still omitted alongside a set min")
end

-- 3. AudioSubType routes to the SFX catalog, and Tag maps per catalog
do
	local opts, isSfx =
		paramsToOptions(params({ SearchKeyword = "door", AudioSubType = "SoundEffect", Tag = "Foley" }), 30, 0)
	assert(isSfx == true, "SoundEffect routes to the SFX catalog")
	assert(opts.filters.categories[1] == "Foley", "Tag becomes an SFX category")
	assert(opts.filters.genres == nil, "SFX search doesn't get a genres filter")

	local musicOpts = paramsToOptions(params({ SearchKeyword = "beat", Tag = "Hip Hop / Rap" }), 30, 0)
	assert(musicOpts.filters.genres[1] == "Hip Hop / Rap", "Tag becomes a music genre")
	assert(musicOpts.filters.categories == nil, "music search doesn't get a categories filter")
end

-- 4. Title/Artist/Album fold into the query (neither endpoint filters on them)
do
	local opts = paramsToOptions(params({ SearchKeyword = "upbeat", Artist = "Daft Punk", Album = "Discovery" }), 30, 0)
	assert(opts.query == "upbeat Daft Punk Discovery", "extra params join the query; got: " .. tostring(opts.query))
end

-- 5. A Tag-only search is valid natively, so the tag doubles as the query
do
	local opts = paramsToOptions(params({ Tag = "Jazz" }), 30, 0)
	assert(opts.query == "Jazz", "Tag stands in as the query when no text is set; got: " .. tostring(opts.query))
	assert(opts.filters.genres[1] == "Jazz", "Tag still applies as a filter")
end

-- 6. Nothing set at all → no query, so the caller can fall back to native
do
	local opts = paramsToOptions(params(), 30, 0)
	assert(opts.query == nil, "no query when every text field is empty")
end

-- 7. Music result mapping matches the native item shape exactly
do
	local result = mapTrackToAudioResult({
		asset_id = "12345",
		name = "Night Drive",
		artist = "Vector",
		genre = "Synthwave",
		genre_slug = "synthwave",
		duration = 184,
		bpm = 120,
		score = 0.87,
		created_at = "2026-01-01",
		updated_at = "2026-02-01",
		creator_name = "Vector Audio",
	})

	-- Every key the engine returns, verified against a live SearchAudioAsync call.
	for _, key in
		{
			"Id",
			"Title",
			"Artist",
			"Description",
			"Duration",
			"Tags",
			"AudioType",
			"IsEndorsed",
			"CreateTime",
			"UpdateTime",
			"Creator",
		}
	do
		assert(result[key] ~= nil, "native key present: " .. key)
	end
	assert(result.Id == 12345 and type(result.Id) == "number", "Id is numeric like native")
	assert(result.Title == "Night Drive", "Title from name")
	assert(result.AudioType == "Music", "AudioType is the plain string here, not an EnumItem")
	assert(result.IsEndorsed == false, "IsEndorsed present and false rather than omitted")
	assert(result.Tags[1] == "Synthwave", "genre surfaces as a tag")
	assert(result.Creator.Name == "Vector Audio", "creator_name maps into Creator.Name")
	assert(result.Creator.Type == 1 and result.Creator.IsVerifiedCreator == false, "Creator shape is complete")

	-- Additive AudioScape fields
	assert(result.AssetId == "12345", "AssetId keeps the string form")
	assert(result.Score == 0.87 and result.Bpm == 120, "Score/Bpm exposed alongside the native shape")
	assert(result.GenreSlug == "synthwave", "GenreSlug exposed")
end

-- 8. SFX mapping splits the delimited tag string and dedupes
do
	local result = mapSfxToAudioResult({
		asset_id = "777",
		name = "Wooden Door Creak",
		description = "A slow creak",
		category = "Foley",
		subcategory = "Doors",
		tags = "door, creak , wood,door",
		duration = 3.2,
		score = 0.5,
		creator_id = 42,
		creator_name = "SFX Co",
	})

	assert(result.AudioType == "SoundEffect", "SFX AudioType string")
	assert(result.Description == "A slow creak", "SFX description maps to Description")
	assert(result.Creator.Id == 42, "SFX creator_id is available and maps to Creator.Id")
	assert(result.Tags[1] == "Foley" and result.Tags[2] == "Doors", "category/subcategory lead the tags")

	local joined = table.concat(result.Tags, "|")
	assert(joined:find("creak", 1, true), "comma-delimited tags are split; got: " .. joined)
	assert(joined:find("wood", 1, true), "whitespace around tags is trimmed; got: " .. joined)
	local doorCount = 0
	for _, tag in result.Tags do
		if tag == "door" then
			doorCount += 1
		end
	end
	assert(doorCount == 1, "duplicate tags collapse; got " .. tostring(doorCount))
end

-- 9. mapSearchResultToPage reads total from meta, not from the page length
do
	local page, total = mapSearchResultToPage({
		tracks = { { asset_id = "1" }, { asset_id = "2" } },
		meta = { total = 250 },
	}, false)
	assert(#page == 2, "page has one entry per track")
	assert(total == 250, "total comes from meta.total; got: " .. tostring(total))

	local emptyPage, emptyTotal = mapSearchResultToPage({ tracks = {} }, false)
	assert(#emptyPage == 0 and emptyTotal == 0, "empty result yields an empty page")
end

-- 10. Pagination: IsFinished, advancing, and refusing to advance past the end
do
	local fetched: { number } = {}
	local function fetchPage(offset: number)
		table.insert(fetched, offset)
		-- 70 results total across 3 pages of 30/30/10.
		local remaining = math.max(0, 70 - offset)
		local count = math.min(30, remaining)
		local page = {}
		for i = 1, count do
			table.insert(page, { Id = offset + i })
		end
		return page, 70
	end

	-- `any` so the analyzer doesn't narrow IsFinished to `false` from the first
	-- assertion and then reject the later comparison against `true`.
	local pages: any = createAudioPages(fetchPage, 30)
	assert(#pages:GetCurrentPage() == 30, "first page has 30 like native")
	assert(not pages.IsFinished, "not finished with 70 total")
	assert(fetched[1] == 0, "first fetch is at offset 0")

	pages:AdvanceToNextPageAsync()
	assert(fetched[2] == 30, "second fetch is at offset 30")
	assert(not pages.IsFinished, "still not finished at 60/70")

	pages:AdvanceToNextPageAsync()
	assert(#pages:GetCurrentPage() == 10, "final page is the remainder")
	assert(pages.IsFinished, "finished once the page runs out")

	local ok, err = pcall(function()
		pages:AdvanceToNextPageAsync()
	end)
	assert(not ok, "advancing past the end errors like native")
	assert(tostring(err):find("no more pages", 1, true), "error explains why; got: " .. tostring(err))
end

-- 11. End to end: SearchAudioAsync hits /v1/search and returns a native-shaped page
do
	local freshSdk, http = newSdk()
	local client = (freshSdk :: any).new("test-key")
	local AssetService = client:getAssetService()

	http:queueResponse(searchResponse({
		{ asset_id = "555", name = "Sunrise", artist = "Aria", genre = "Ambient", duration = 200 },
	}, 1))

	local pages = AssetService:SearchAudioAsync(params({ SearchKeyword = "calm morning" }))
	local page = pages:GetCurrentPage()

	assert(#page == 1, "one result mapped through")
	assert(page[1].Title == "Sunrise", "native Title field populated")
	assert(page[1].Id == 555, "native Id field populated")
	assert(pages.IsFinished == true, "single-page result is finished")

	local recorded = http.requests[1]
	assert(recorded.method == "POST", "music search uses POST /v1/search")
	assert(recorded.url:find("/v1/search", 1, true), "hit the music endpoint")

	local decoded: any = serde.decode("json", recorded.body)
	assert(decoded.query == "calm morning", "SearchKeyword became the query")
	assert(decoded.limit == 30, "defaults to native's 30-per-page")
	assert(decoded.filters == nil, "unset sentinels produced no filters on the wire")
end

-- 12. AudioSubType SoundEffect routes to the SFX endpoint instead
do
	local freshSdk, http = newSdk()
	local client = (freshSdk :: any).new("test-key")
	local AssetService = client:getAssetService()

	http:queueResponse({
		Success = true,
		StatusCode = 200,
		Body = serde.encode("json", {
			tracks = { { asset_id = "9", name = "Thud", category = "Foley", duration = 1 } },
			categories = {},
			subcategories = {},
			meta = { total = 1, limit = 30, offset = 0, search_method = "semantic" },
		}),
	})

	local pages = AssetService:SearchAudioAsync(params({ SearchKeyword = "impact", AudioSubType = "SoundEffect" }))
	assert(pages:GetCurrentPage()[1].AudioType == "SoundEffect", "SFX results carry the SoundEffect type")
	assert(http.requests[1].url:find("/v1/sfx/search", 1, true), "routed to the SFX endpoint")
end

-- 13. A failing request with fallback disabled surfaces the error
do
	local freshSdk, http = newSdk()
	local client = (freshSdk :: any).new("test-key")
	local AssetService = client:getAssetService({ fallback = false })

	http:queueResponse({ Success = false, StatusCode = 500, Body = "" })

	local ok, err = pcall(function()
		return AssetService:SearchAudioAsync(params({ SearchKeyword = "anything" }))
	end)
	assert(not ok, "SearchAudioAsync raises rather than returning an error value, like native")
	assert(tostring(err):find("Server error", 1, true), "surfaces the underlying error; got: " .. tostring(err))
end

-- 14. Unrecognised members forward to the real AssetService rather than nil
do
	local freshSdk = (newSdk())
	local client = (freshSdk :: any).new("test-key")
	local AssetService = client:getAssetService()

	-- The mock game's AssetService stub is what __index should reach for.
	-- Nothing overrides SearchAudio, so it must resolve to our shim's alias.
	assert(type(AssetService.SearchAudioAsync) == "function", "SearchAudioAsync is overridden")
	assert(AssetService.SearchAudio == AssetService.SearchAudioAsync, "deprecated SearchAudio aliases the same shim")
end
