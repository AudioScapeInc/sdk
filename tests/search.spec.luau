--!strict
-- Unit test for client:search. Existing query-only behavior (regression
-- coverage) plus the v0.12.0 additions:
--   * asset_ids batch lookup via the same method
--   * accepting either query or asset_ids
--   * rejecting when both are missing / empty
--   * meta.missing_ids round-trips through the SearchResult shape

local serde = require("@lune/serde")
local mockHttp = require("./_harness/mockHttp")
local loadSdk = require("./_harness/loadSdk").loadSdk

local function emptyResponse(): mockHttp.Response
	return {
		Success = true,
		StatusCode = 200,
		Body = serde.encode("json", {
			tracks = {},
			artists = {},
			albums = {},
			meta = { total = 0, limit = 20, offset = 0, search_method = "semantic" },
		}),
	}
end

local function batchResponse(): mockHttp.Response
	return {
		Success = true,
		StatusCode = 200,
		Body = serde.encode("json", {
			tracks = { { asset_id = "111" }, { asset_id = "222" } },
			artists = {},
			albums = {},
			meta = {
				total = 2,
				limit = 100,
				offset = 0,
				search_method = "ids-batch",
				missing_ids = { "999" },
			},
		}),
	}
end

-- 1. Query-only call goes to POST /v1/search with body.query and no asset_ids
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	http:queueResponse(emptyResponse())
	local result, err = client:search({ query = "chill lo-fi", limit = 5 })
	assert(result and not err, "query-only search ok; err: " .. tostring(err))

	local recorded = http.requests[1]
	assert(recorded.method == "POST", "search uses POST")
	assert(recorded.url:find("/v1/search", 1, true), "URL contains /v1/search")

	local decoded: any = serde.decode("json", recorded.body)
	assert(decoded.query == "chill lo-fi", "body.query echoes input; got: " .. tostring(decoded.query))
	assert(decoded.limit == 5, "body.limit carried; got: " .. tostring(decoded.limit))
	assert(decoded.asset_ids == nil, "body.asset_ids absent on query-only call")
end

-- 2. asset_ids-only call: query absent, body.asset_ids present
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	http:queueResponse(batchResponse())
	local result, err = client:search({ asset_ids = { "111", "222", "999" } })
	assert(result and not err, "asset_ids-only search ok; err: " .. tostring(err))

	local decoded: any = serde.decode("json", http.requests[1].body)
	assert(decoded.query == nil, "body.query absent when only asset_ids supplied")
	assert(type(decoded.asset_ids) == "table" and #decoded.asset_ids == 3, "body.asset_ids carries 3 ids")
	assert(decoded.asset_ids[1] == "111", "input order preserved")

	-- meta.missing_ids round-trips via the SearchResult shape
	assert(
		result.meta.missing_ids and #result.meta.missing_ids == 1 and result.meta.missing_ids[1] == "999",
		"meta.missing_ids surfaces in result"
	)
	assert(result.meta.search_method == "ids-batch", "search_method propagates")
end

-- 3. Both query and asset_ids: SDK forwards both; server picks priority
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	http:queueResponse(emptyResponse())
	client:search({ query = "fallback text", asset_ids = { "111" } })

	local decoded: any = serde.decode("json", http.requests[1].body)
	assert(decoded.query == "fallback text", "body.query forwarded when both present")
	assert(type(decoded.asset_ids) == "table" and #decoded.asset_ids == 1, "body.asset_ids forwarded when both present")
end

-- 4. Filters and offset propagate alongside asset_ids (server bypasses filters
--    on ID lookup, but the SDK shouldn't strip them — that's the API's call)
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	http:queueResponse(emptyResponse())
	client:search({
		query = "anything",
		offset = 40,
		filters = { genres = { "Hip Hop / Rap" }, duration = { min = 60, max = 180 } },
	})

	local decoded: any = serde.decode("json", http.requests[1].body)
	assert(decoded.offset == 40, "body.offset carried; got: " .. tostring(decoded.offset))
	assert(type(decoded.filters) == "table", "body.filters is a table")
	assert(decoded.filters.genres[1] == "Hip Hop / Rap", "canonical-form genre passes through unchanged")
end

-- 5. Validation: neither query nor asset_ids → pre-flight error, no HTTP
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	local r, e = client:search({} :: any)
	assert(r == nil and e, "empty options rejected pre-flight")
	assert(
		e:find("query string or a non-empty asset_ids array", 1, true),
		"err mentions both shapes; got: " .. tostring(e)
	)
	assert(#http.requests == 0, "no HTTP for empty options")
end

-- 6. Validation: empty query string and no asset_ids → rejected
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	local r, e = client:search({ query = "" })
	assert(r == nil and e, "empty query string rejected pre-flight")
	assert(
		e:find("query string or a non-empty asset_ids array", 1, true),
		"err mentions both shapes; got: " .. tostring(e)
	)
	assert(#http.requests == 0, "no HTTP for empty query string")
end

-- 7. Validation: empty asset_ids array (and no query) → rejected
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	local r, e = client:search({ asset_ids = {} })
	assert(r == nil and e, "empty asset_ids rejected pre-flight")
	assert(
		e:find("query string or a non-empty asset_ids array", 1, true),
		"err mentions both shapes; got: " .. tostring(e)
	)
	assert(#http.requests == 0, "no HTTP for empty asset_ids")
end
