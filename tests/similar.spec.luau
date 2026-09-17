--!strict
-- Unit test for client:similar polymorphic input. Covers:
--   * string input
--   * Track-shaped table (asset_id only)
--   * legacy options-table form (asset_id + limit + filters + playerId)
--   * extras arg overrides input-table fields when both present
--   * extras arg with bare-string input
--   * validation: empty / unrecognized input shape → pre-flight error
--
-- The Sound/AudioPlayer Instance arms are exercised by the Open Cloud smoke
-- (real Roblox engine where typeof returns "Instance"); see
-- tests/openCloud/smokeScript.luau.

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
			-- Decode %XX percent-encodings (UrlEncode roundtrip)
			out[k] = v:gsub("%%(%x%x)", function(h)
				return string.char(tonumber(h, 16) :: number)
			end)
		end
	end
	return out
end

-- 1. string input
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	http:queueResponse(emptyResponse())
	local result, err = client:similar("rbxassetid://1234")
	assert(result and not err, "string input should succeed; err: " .. tostring(err))
	assert(#http.requests == 1, "exactly one HTTP call")

	local q = decodeQuery(http.requests[1].url)
	assert(q.asset_id == "1234", "string input → asset_id=1234 on the wire; got: " .. tostring(q.asset_id))
	assert(q.limit == nil, "no limit when extras omitted; got: " .. tostring(q.limit))
end

-- 2. Track-shaped table (asset_id only)
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	http:queueResponse(emptyResponse())
	client:similar({ asset_id = "5678", name = "Some Song", artist = "Some Artist" })

	local q = decodeQuery(http.requests[1].url)
	assert(q.asset_id == "5678", "Track table → asset_id=5678; got: " .. tostring(q.asset_id))
end

-- 3. Legacy options-table form (asset_id + limit + filters + playerId)
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	http:queueResponse(emptyResponse())
	client:similar({
		asset_id = "9999",
		limit = 5,
		offset = 10,
		playerId = 42,
		filters = { genres = { "electronic" } },
	})

	local recorded = http.requests[1]
	local q = decodeQuery(recorded.url)
	assert(q.asset_id == "9999", "legacy form passes asset_id")
	assert(q.limit == "5", "legacy form passes limit; got: " .. tostring(q.limit))
	assert(q.offset == "10", "legacy form passes offset; got: " .. tostring(q.offset))
	assert(
		q.filters and q.filters:find("electronic", 1, true),
		"legacy filters JSON-encoded; got: " .. tostring(q.filters)
	)
	assert(
		recorded.headers and recorded.headers["X-Player-Id"] == "42",
		"legacy playerId → X-Player-Id header; got: " .. tostring(recorded.headers and recorded.headers["X-Player-Id"])
	)
end

-- 4. extras arg overrides input-table fields when both present
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	http:queueResponse(emptyResponse())
	-- Input has limit=5, extras has limit=20 → extras wins (whole-bag rule)
	client:similar({ asset_id = "111", limit = 5 }, { limit = 20, playerId = 7 })

	local recorded = http.requests[1]
	local q = decodeQuery(recorded.url)
	assert(q.limit == "20", "extras.limit overrides input.limit; got: " .. tostring(q.limit))
	assert(
		recorded.headers and recorded.headers["X-Player-Id"] == "7",
		"extras.playerId wins; got: " .. tostring(recorded.headers and recorded.headers["X-Player-Id"])
	)
end

-- 5. extras arg with bare-string input
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	http:queueResponse(emptyResponse())
	client:similar("222", { limit = 3, filters = { genres = { "rock" } } })

	local q = decodeQuery(http.requests[1].url)
	assert(q.asset_id == "222", "string-input + extras passes asset_id=222")
	assert(q.limit == "3", "extras.limit=3 carried")
	assert(q.filters and q.filters:find("rock", 1, true), "extras.filters carried; got: " .. tostring(q.filters))
end

-- 6. Validation: nil input
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	local r, e = client:similar(nil)
	assert(r == nil, "nil input → nil result")
	assert(
		e and e:find("track table, a Sound, or an AudioPlayer", 1, true),
		"err mentions all four shapes; got: " .. tostring(e)
	)
	assert(#http.requests == 0, "no HTTP for invalid input")
end

-- 7. Validation: empty asset_id in table
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	local r, e = client:similar({ asset_id = "" })
	assert(r == nil and e, "empty asset_id rejected pre-flight")
	assert(#http.requests == 0, "no HTTP for empty asset_id")
end

-- 8. max_score on the wire (extras form)
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	http:queueResponse(emptyResponse())
	client:similar("333", { max_score = 0.85 })

	local q = decodeQuery(http.requests[1].url)
	assert(q.max_score == "0.85", "extras.max_score serializes as 0.85; got: " .. tostring(q.max_score))
end

-- 9. max_score on the wire (legacy options-table form)
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	http:queueResponse(emptyResponse())
	client:similar({ asset_id = "444", max_score = 0.9 })

	local q = decodeQuery(http.requests[1].url)
	assert(q.max_score == "0.9", "legacy max_score serializes as 0.9; got: " .. tostring(q.max_score))
end

-- 10. dedupe=true on the wire
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	http:queueResponse(emptyResponse())
	client:similar("555", { dedupe = true })

	local q = decodeQuery(http.requests[1].url)
	assert(q.dedupe == "true", "dedupe=true serializes as 'true'; got: " .. tostring(q.dedupe))
	assert(q.max_score == nil, "dedupe alone does not also set max_score on the wire; got: " .. tostring(q.max_score))
end

-- 11. dedupe=false omitted from the wire (no point sending the no-op default)
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	http:queueResponse(emptyResponse())
	client:similar("666", { dedupe = false })

	local q = decodeQuery(http.requests[1].url)
	assert(q.dedupe == nil, "dedupe=false should not appear on the wire; got: " .. tostring(q.dedupe))
end

-- 12. extras override input table for max_score / dedupe (whole-bag rule)
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	http:queueResponse(emptyResponse())
	-- Input has max_score=0.5; extras has max_score=0.95 → extras wins.
	client:similar({ asset_id = "777", max_score = 0.5 }, { max_score = 0.95, dedupe = true })

	local q = decodeQuery(http.requests[1].url)
	assert(q.max_score == "0.95", "extras.max_score wins; got: " .. tostring(q.max_score))
	assert(q.dedupe == "true", "extras.dedupe carried alongside max_score; got: " .. tostring(q.dedupe))
end

-- 13. Seed list: array of strings → asset_ids CSV on the wire, no asset_id
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	http:queueResponse(emptyResponse())
	local result, err = client:similar({ "1234", "rbxassetid://5678" }, { limit = 20 })
	assert(result and not err, "seed list should succeed; err: " .. tostring(err))
	assert(#http.requests == 1, "exactly one HTTP call for a seed list")

	local q = decodeQuery(http.requests[1].url)
	assert(q.asset_ids == "1234,5678", "seed list → asset_ids=1234,5678 on the wire; got: " .. tostring(q.asset_ids))
	assert(q.asset_id == nil, "seed list sends no asset_id; got: " .. tostring(q.asset_id))
	assert(q.limit == "20", "extras.limit carried with a seed list; got: " .. tostring(q.limit))
end

-- 14. Seed list: array of Track tables (a playlist's tracks)
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	http:queueResponse(emptyResponse())
	client:similar({ { asset_id = "11", name = "A" }, { asset_id = "22", name = "B" } })

	local q = decodeQuery(http.requests[1].url)
	assert(q.asset_ids == "11,22", "Track tables → asset_ids=11,22; got: " .. tostring(q.asset_ids))
end

-- 15. Seed list: legacy options-table form carries limit/filters/playerId
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	http:queueResponse(emptyResponse())
	client:similar({ asset_ids = { "33", "44" }, limit = 5, playerId = 42, filters = { genres = { "rock" } } })

	local recorded = http.requests[1]
	local q = decodeQuery(recorded.url)
	assert(q.asset_ids == "33,44", "options-table asset_ids → CSV; got: " .. tostring(q.asset_ids))
	assert(q.asset_id == nil, "options-table seed list sends no asset_id; got: " .. tostring(q.asset_id))
	assert(q.limit == "5", "options-table limit carried; got: " .. tostring(q.limit))
	assert(q.filters and q.filters:find("rock", 1, true), "options-table filters carried; got: " .. tostring(q.filters))
	assert(
		recorded.headers and recorded.headers["X-Player-Id"] == "42",
		"options-table playerId → X-Player-Id; got: " .. tostring(recorded.headers and recorded.headers["X-Player-Id"])
	)
end

-- 16. Validation: an element that doesn't resolve → pre-flight error naming it, no HTTP
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	-- Mixed list: strict mode infers the array type from the first element,
	-- so annotate to test the runtime check rather than the type checker.
	local seeds: { any } = { "1234", { name = "no id" } }
	local r, e = client:similar(seeds)
	assert(r == nil, "bad element → nil result")
	assert(e and e:find("asset_ids[2]", 1, true), "error names the offending index; got: " .. tostring(e))
	assert(#http.requests == 0, "no HTTP for an invalid seed list")
end

-- 17. Validation: empty asset_ids
do
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local client = (sdk :: any).new("test-key")

	local r, e = client:similar({ asset_ids = {} })
	assert(r == nil, "empty list → nil result")
	assert(e and e:find("non-empty", 1, true), "empty list rejected pre-flight; got: " .. tostring(e))
	assert(#http.requests == 0, "no HTTP for an empty seed list")
end
