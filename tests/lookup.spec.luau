--!strict
-- Unit test for client:lookup — sugar over client:search for known-asset-ID
-- batch lookups. Covers:
--   * happy path: posts /v1/search with asset_ids, no query, no filters
--   * playerId forwarded to X-Player-Id header
--   * validation: nil input, non-table input, missing asset_ids field,
--     empty asset_ids array — all rejected pre-flight, no HTTP

local serde = require("@lune/serde")
local mockHttp = require("./_harness/mockHttp")
local loadSdk = require("./_harness/loadSdk").loadSdk

local function lookupResponse(): mockHttp.Response
	return {
		Success = true,
		StatusCode = 200,
		Body = serde.encode("json", {
			tracks = {
				{ asset_id = "111" },
				{ asset_id = "222" },
			},
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

-- 1. Happy path — body carries asset_ids only, hits POST /v1/search
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	http:queueResponse(lookupResponse())
	local result, err = client:lookup({ asset_ids = { "111", "222", "999" } })
	assert(result and not err, "lookup happy path; err: " .. tostring(err))
	assert(#http.requests == 1, "exactly one HTTP call")

	local recorded = http.requests[1]
	assert(recorded.method == "POST", "lookup goes through POST /v1/search; got: " .. tostring(recorded.method))
	assert(
		recorded.url:find("/v1/search", 1, true) and not recorded.url:find("?", 1, true),
		"URL is /v1/search with no query string; got: " .. recorded.url
	)
	assert(recorded.headers and recorded.headers["x-api-key"] == "test-key", "API key header present")

	local decoded: any = serde.decode("json", recorded.body)
	assert(type(decoded.asset_ids) == "table", "body.asset_ids is a table")
	assert(#decoded.asset_ids == 3, "all 3 ids round-tripped; got " .. tostring(#decoded.asset_ids))
	assert(
		decoded.asset_ids[1] == "111" and decoded.asset_ids[2] == "222" and decoded.asset_ids[3] == "999",
		"input order preserved"
	)
	assert(decoded.query == nil, "no query field in body when only asset_ids given")
	assert(decoded.filters == nil, "no filters field in body — explicit ID lookups bypass filters server-side")
	assert(decoded.limit == nil, "no limit field when not supplied")
	assert(decoded.offset == nil, "no offset field when not supplied")

	-- meta.missing_ids round-trips through the SearchResult shape
	assert(
		result.meta.search_method == "ids-batch",
		"search_method propagates; got: " .. tostring(result.meta.search_method)
	)
	assert(
		result.meta.missing_ids and #result.meta.missing_ids == 1 and result.meta.missing_ids[1] == "999",
		"meta.missing_ids surfaces in result"
	)
end

-- 2. playerId forwarded to X-Player-Id header
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	http:queueResponse(lookupResponse())
	client:lookup({ asset_ids = { "1234" }, playerId = 42 })

	local recorded = http.requests[1]
	assert(
		recorded.headers and recorded.headers["X-Player-Id"] == "42",
		"X-Player-Id header set; got: " .. tostring(recorded.headers and recorded.headers["X-Player-Id"])
	)
end

-- 3. Validation — nil input
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	local r, e = client:lookup(nil)
	assert(r == nil, "nil input → nil result")
	assert(
		e and e:find("non-empty asset_ids array", 1, true),
		"err mentions non-empty asset_ids array; got: " .. tostring(e)
	)
	assert(#http.requests == 0, "no HTTP for nil input")
end

-- 4. Validation — non-table input
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	local r, e = client:lookup("not-a-table" :: any)
	assert(r == nil and e, "non-table input rejected pre-flight")
	assert(e:find("non-empty asset_ids array", 1, true), "err mentions non-empty asset_ids array; got: " .. tostring(e))
	assert(#http.requests == 0, "no HTTP for non-table input")
end

-- 5. Validation — table without asset_ids field
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	local r, e = client:lookup({} :: any)
	assert(r == nil and e, "missing asset_ids rejected pre-flight")
	assert(e:find("non-empty asset_ids array", 1, true), "err mentions non-empty asset_ids array; got: " .. tostring(e))
	assert(#http.requests == 0, "no HTTP for missing asset_ids")
end

-- 6. Validation — empty asset_ids array
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	local r, e = client:lookup({ asset_ids = {} })
	assert(r == nil and e, "empty asset_ids array rejected pre-flight")
	assert(e:find("non-empty asset_ids array", 1, true), "err mentions non-empty asset_ids array; got: " .. tostring(e))
	assert(#http.requests == 0, "no HTTP for empty asset_ids")
end
