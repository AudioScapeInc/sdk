--!strict
-- Unit test for getStructure — verifies the cache hits on the second call.

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
	Body = require("@lune/serde").encode("json", fixture),
})

-- empty asset_id rejected before any HTTP call
local rejected, err = client:getStructure({ asset_id = "" })
assert(
	rejected == nil and err and err:find("non-empty asset_id", 1, true),
	"empty asset_id should be rejected pre-flight; got: " .. tostring(err)
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

-- different asset_id is a separate cache key
http:queueResponse({
	Success = true,
	StatusCode = 200,
	Body = require("@lune/serde").encode("json", { asset_id = "xyz", sections = {}, phrases = {} }),
})
local other = client:getStructure({ asset_id = "xyz" })
assert(other and other.asset_id == "xyz", "different asset_id pulls fresh result")
assert(#http.requests == 2, "second asset should issue another HTTP call")
