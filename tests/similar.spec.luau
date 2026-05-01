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
