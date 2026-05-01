--!strict
-- Unit test for client:sfxSimilar polymorphic input. Mirrors similar.spec
-- but for the /v1/sfx/similar endpoint with SFX-shaped filters
-- (categories/subcategories instead of genres). Sound/AudioPlayer Instance
-- arms covered by the Open Cloud smoke.

local serde = require("@lune/serde")
local mockHttp = require("./_harness/mockHttp")
local loadSdk = require("./_harness/loadSdk").loadSdk

local function emptyResponse(): mockHttp.Response
	return {
		Success = true,
		StatusCode = 200,
		Body = serde.encode("json", { tracks = {}, meta = { total = 0, limit = 0, offset = 0 } }),
	}
end

local function decodeQuery(url: string): { [string]: string }
	local q = url:match("%?(.+)$")
	local out: { [string]: string } = {}
	if not q then
		return out
	end
	for pair in q:gmatch("[^&]+") do
		local k, v = pair:match("^([^=]+)=(.*)$")
		if k and v then
			out[k] = v:gsub("%%(%x%x)", function(h)
				return string.char(tonumber(h, 16) :: number)
			end)
		end
	end
	return out
end

-- Endpoint shape sanity: every test case hits /v1/sfx/similar
local function assertEndpoint(http: mockHttp.MockHttp)
	assert(http.requests[1].method == "GET", "sfxSimilar uses GET")
	assert(
		http.requests[1].url:find("/v1/sfx/similar", 1, true),
		"URL contains /v1/sfx/similar; got " .. http.requests[1].url
	)
end

-- 1. string input
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	http:queueResponse(emptyResponse())
	local result, err = client:sfxSimilar("rbxassetid://44")
	assert(result and not err, "string input ok; err: " .. tostring(err))
	assertEndpoint(http)
	local q = decodeQuery(http.requests[1].url)
	assert(q.asset_id == "44", "asset_id peeled to 44; got: " .. tostring(q.asset_id))
end

-- 2. SfxTrack-shaped table
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	http:queueResponse(emptyResponse())
	client:sfxSimilar({ asset_id = "55", name = "Boom", category = "WEAPON" })
	assertEndpoint(http)
	local q = decodeQuery(http.requests[1].url)
	assert(q.asset_id == "55", "SfxTrack table → asset_id=55; got: " .. tostring(q.asset_id))
end

-- 3. Legacy options-table form with SFX filters
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	http:queueResponse(emptyResponse())
	client:sfxSimilar({
		asset_id = "66",
		limit = 8,
		playerId = 99,
		filters = { categories = { "AMBIENCE" }, subcategories = { "WIND" } },
	})

	local recorded = http.requests[1]
	local q = decodeQuery(recorded.url)
	assert(q.asset_id == "66", "legacy form passes asset_id=66")
	assert(q.limit == "8", "limit; got: " .. tostring(q.limit))
	assert(
		q.filters and q.filters:find("AMBIENCE", 1, true) and q.filters:find("WIND", 1, true),
		"filters carry categories+subcategories; got: " .. tostring(q.filters)
	)
	assert(recorded.headers and recorded.headers["X-Player-Id"] == "99", "X-Player-Id header")
end

-- 4. extras overrides input table
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	http:queueResponse(emptyResponse())
	client:sfxSimilar({ asset_id = "77", limit = 1 }, { limit = 50, filters = { categories = { "WEAPON" } } })

	local q = decodeQuery(http.requests[1].url)
	assert(q.limit == "50", "extras.limit wins; got: " .. tostring(q.limit))
	assert(q.filters and q.filters:find("WEAPON", 1, true), "extras.filters wins; got: " .. tostring(q.filters))
end

-- 5. Validation
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	local r, e = client:sfxSimilar(nil)
	assert(r == nil and e, "nil input rejected")
	assert(
		e:find("track table, a Sound, or an AudioPlayer", 1, true),
		"err mentions all four shapes; got: " .. tostring(e)
	)
	assert(#http.requests == 0, "no HTTP for invalid input")
end
