--!strict
-- Unit test for buildQuery — query-string assembly with nil-skip + URL encoding.

local mockHttp = require("./_harness/mockHttp")
local loadSdk = require("./_harness/loadSdk").loadSdk

local sdk = loadSdk({ http = mockHttp.new() })
local buildQuery = (sdk :: any).__internal.buildQuery

-- empty input → empty string (no leading "?")
assert(buildQuery({}) == "", "empty params should produce no query string")

-- nil values are skipped
assert(buildQuery({ a = nil }) == "", "all-nil params should produce no query string")

-- single key
assert(buildQuery({ q = "hello" }) == "?q=hello", "single param formats as ?key=value")

-- numeric values are tostring'd
assert(buildQuery({ limit = 10 }) == "?limit=10", "number values are tostring'd")

-- URL-encodes special chars
local encoded = buildQuery({ q = "chill beats" })
assert(encoded == "?q=chill%20beats" or encoded == "?q=chill+beats", "spaces are encoded; got: " .. encoded)

-- multiple params (order non-deterministic in Lua) — parse and verify membership
local multi = buildQuery({ a = "1", b = "2", c = "3" })
assert(multi:sub(1, 1) == "?", "multi-param string should start with ?")
local body = multi:sub(2)
local parts = {}
for piece in body:gmatch("[^&]+") do
	table.insert(parts, piece)
end
assert(#parts == 3, "expected 3 params, got " .. #parts)
local seen: { [string]: boolean } = {}
for _, part in parts do
	seen[part] = true
end
assert(seen["a=1"] and seen["b=2"] and seen["c=3"], "expected a=1, b=2, c=3 — got: " .. multi)

-- nil interleaved with non-nil
local mixed = buildQuery({ q = "x", missing = nil, limit = 5 })
assert(mixed:find("q=x", 1, true), "expected q=x in mixed query")
assert(mixed:find("limit=5", 1, true), "expected limit=5 in mixed query")
assert(not mixed:find("missing", 1, true), "missing should be skipped")

-- table values (e.g. `filters` for GET /v1/similar) are JSON-encoded then
-- URL-encoded into a single querystring parameter
local withFilters = buildQuery({ asset_id = "abc", filters = { genres = { "ambient" } } })
assert(withFilters:find("asset_id=abc", 1, true), "asset_id present")
assert(withFilters:find("filters=", 1, true), "filters key present; got: " .. withFilters)
-- The encoded JSON should contain the URL-escaped braces and the genres key
assert(
	withFilters:find("filters=%%7B", 1, false),
	"filters value starts with URL-encoded JSON object; got: " .. withFilters
)
