--!strict
-- Unit test for getStructure — verifies the cache hits on the second call,
-- the polymorphic input shapes (string, Track-table, options-table-form),
-- and that cache keys are the resolved asset_id (so passing a Track and a
-- bare string for the same asset deduplicate to one HTTP call).

local serde = require("@lune/serde")
local mockHttp = require("./_harness/mockHttp")
local loadSdk = require("./_harness/loadSdk").loadSdk

local http = mockHttp.new()
local sdk = loadSdk({ http = http })
local client = (sdk :: any).new("test-key")

local fixture = {
	asset_id = "abc",
	duration = 60,
	bpm = 120,
	beat_grid = { times = { 0, 0.5, 1.0 }, downbeats = { 0 } },
	sections = { { start = 0, ["end"] = 60, label = "loop" } },
	phrases = {},
}

http:queueResponse({
	Success = true,
	StatusCode = 200,
	StatusMessage = "OK",
	Body = serde.encode("json", fixture),
})

-- empty asset_id rejected before any HTTP call
local rejected, err = client:getStructure({ asset_id = "" })
assert(
	rejected == nil and err and err:find("track table, a Sound, or an AudioPlayer", 1, true),
	"empty asset_id should be rejected pre-flight with the four-shape message; got: " .. tostring(err)
)
assert(#http.requests == 0, "no HTTP call should be issued for invalid input")

-- first call hits HTTP
local result, err1 = client:getStructure({ asset_id = "abc" })
assert(result and not err1, "first call should succeed; err: " .. tostring(err1))
assert(result.asset_id == "abc", "decoded asset_id round-trips")
assert(result.bpm == 120, "decoded bpm round-trips")
assert(#http.requests == 1, "first call should issue exactly one HTTP request, got " .. #http.requests)

-- second call returns cached value — no extra HTTP request
local result2, err2 = client:getStructure({ asset_id = "abc" })
assert(result2 and not err2, "second call should succeed from cache")
assert(#http.requests == 1, "second call should NOT issue HTTP, got " .. #http.requests)

-- bare string with the same asset_id should also hit the cache (cache key
-- is the resolved id, not the input shape)
local result3 = client:getStructure("rbxassetid://abc")
-- Note: "rbxassetid://abc" doesn't have digits, so resolveAssetId returns
-- nil — exercise this with a numeric id below instead.
assert(result3 == nil, "non-numeric URI string fails to resolve; got: " .. tostring(result3))

-- different asset_id (table form) is a separate cache key
http:queueResponse({
	Success = true,
	StatusCode = 200,
	Body = serde.encode("json", { asset_id = "xyz", sections = {}, phrases = {} }),
})
local other = client:getStructure({ asset_id = "xyz" })
assert(other and other.asset_id == "xyz", "different asset_id pulls fresh result")
assert(#http.requests == 2, "second asset should issue another HTTP call")

-- bare-string input with numeric id resolves and caches
http:queueResponse({
	Success = true,
	StatusCode = 200,
	Body = serde.encode("json", { asset_id = "1234", sections = {}, phrases = {} }),
})
local fromString = client:getStructure("rbxassetid://1234")
assert(
	fromString and fromString.asset_id == "1234",
	"string input resolves; got: " .. tostring(fromString and fromString.asset_id)
)
assert(#http.requests == 3, "string-input issues a fresh HTTP call; got requests: " .. #http.requests)

-- second call with bare numeric form hits the same cache as the URI form
local fromBareNumeric = client:getStructure("1234")
assert(fromBareNumeric and fromBareNumeric.asset_id == "1234", "bare numeric form resolves to '1234'")
assert(#http.requests == 3, "cache hit across input shapes (URI then bare); got requests: " .. #http.requests)

-- Track-shaped table also resolves through the cache for the same id
local fromTrack = client:getStructure({ asset_id = "1234", name = "Some", artist = "Track" })
assert(fromTrack and fromTrack.asset_id == "1234", "Track-table form resolves to '1234'")
assert(#http.requests == 3, "Track-table form also hits the cache; got: " .. #http.requests)

-- Track-table form with extras passes playerId through to the request header
do
	http:reset()
	http:queueResponse({
		Success = true,
		StatusCode = 200,
		Body = serde.encode("json", { asset_id = "newid", sections = {}, phrases = {} }),
	})
	client:getStructure({ asset_id = "newid" }, { playerId = 555 })
	assert(#http.requests == 1, "exactly one HTTP call for new asset")
	local recorded = http.requests[1]
	assert(
		recorded.headers and recorded.headers["X-Player-Id"] == "555",
		"extras.playerId → X-Player-Id header; got: " .. tostring(recorded.headers and recorded.headers["X-Player-Id"])
	)
end

-- include_metadata: forwards in the body, forks the cache per variant, and
-- the authored pairs round-trip on sections
do
	http:reset()
	http:queueResponse({
		Success = true,
		StatusCode = 200,
		Body = serde.encode("json", {
			asset_id = "777",
			sections = {
				{
					start = 0.78,
					["end"] = 5.64,
					label = "light_cue_1",
					metadata = { type = "lighting_cluster", amount = 5 },
				},
			},
			phrases = {},
		}),
	})
	local rich, richErr = client:getStructure({ asset_id = "777", include_metadata = true })
	assert(rich and not richErr, "metadata variant should succeed; err: " .. tostring(richErr))
	assert(#http.requests == 1, "one HTTP call for the metadata variant")
	local sent = serde.decode("json", http.requests[1].body)
	assert(sent.include_metadata == true, "include_metadata=true forwarded in the body")
	assert(
		rich.sections[1].metadata and rich.sections[1].metadata.type == "lighting_cluster",
		"authored pairs round-trip on the section"
	)
	assert(rich.sections[1].metadata.amount == 5, "numeric metadata values survive")

	-- plain call for the same asset is a cache MISS (different variant) and
	-- must not send the flag
	http:queueResponse({
		Success = true,
		StatusCode = 200,
		Body = serde.encode("json", { asset_id = "777", sections = {}, phrases = {} }),
	})
	local plain = client:getStructure({ asset_id = "777" })
	assert(plain, "plain variant fetches")
	assert(#http.requests == 2, "plain variant is a separate cache entry; got " .. #http.requests)
	local sentPlain = serde.decode("json", http.requests[2].body)
	assert(sentPlain.include_metadata == nil, "plain call omits the flag from the body")

	-- and each variant now serves from its own cache slot
	client:getStructure({ asset_id = "777", include_metadata = true })
	client:getStructure({ asset_id = "777" })
	assert(#http.requests == 2, "both variants cached independently; got " .. #http.requests)
end
