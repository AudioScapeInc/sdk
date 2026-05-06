--!strict
-- Unit test for the GET requestGet() helper, exercised via client:browse.
-- Covers happy path, query-string assembly, header propagation, and 5xx mapping.

local serde = require("@lune/serde")
local mockHttp = require("./_harness/mockHttp")
local loadSdk = require("./_harness/loadSdk").loadSdk

local http = mockHttp.new()
local sdk = loadSdk({ http = http })
local client = (sdk :: any).new("test-key")

-- happy path: trending browse
http:queueResponse({
	Success = true,
	StatusCode = 200,
	Body = serde.encode("json", { tracks = {}, meta = { total = 0, limit = 10, offset = 0, type = "trending" } }),
})
local result, err = client:browse({ type = "trending", limit = 10 })
assert(result and not err, "browse trending should succeed; err: " .. tostring(err))
assert(#http.requests == 1, "exactly one HTTP call")

local recorded = http.requests[1]
assert(recorded.method == "GET", "browse v0.10 uses GET, got " .. recorded.method)
assert(recorded.url:find("/v1/browse", 1, true), "URL contains /v1/browse")
-- query-string presence (order non-deterministic; check membership)
assert(recorded.url:find("type=trending", 1, true), "type=trending in query; got " .. recorded.url)
assert(recorded.url:find("limit=10", 1, true), "limit=10 in query; got " .. recorded.url)
assert(recorded.headers and recorded.headers["x-api-key"] == "test-key", "x-api-key set")

-- nil fields skipped from query string
http:reset()
http:queueResponse({ Success = true, StatusCode = 200, Body = "{}" })
client:browse({ type = "genre", name = "jazz" })
recorded = http.requests[1]
assert(not recorded.url:find("offset", 1, true), "nil offset should not appear in URL; got " .. recorded.url)
assert(not recorded.url:find("limit", 1, true), "nil limit should not appear in URL")
assert(recorded.url:find("name=jazz", 1, true), "name=jazz present")

-- pre-flight validation: bad type rejected
http:reset()
local rejected, badErr = client:browse({ type = "not-a-type" })
assert(rejected == nil, "bad type rejected without HTTP")
assert(
	badErr and badErr:find("artist, album, genre, mood, trending", 1, true),
	"err lists valid types; got: " .. tostring(badErr)
)
assert(#http.requests == 0, "no HTTP for invalid type")

-- 5xx → server error message. Re-declare locals so luau-lsp doesn't narrow
-- `err` to one specific status string after the first assert.
do
	http:reset()
	http:queueResponse({ Success = false, StatusCode = 503, Body = "" })
	local r, e = client:browse({ type = "trending" })
	assert(r == nil and e == "Server error — try again later (503)", "got: " .. tostring(e))
end

-- 429 → rate-limit message
do
	http:reset()
	http:queueResponse({ Success = false, StatusCode = 429, Body = "" })
	local r, e = client:browse({ type = "trending" })
	assert(r == nil and e == "Rate limited — too many requests (429)", "got: " .. tostring(e))
end

-- sort: every accepted value forwards into the query string verbatim
for _, sortMode in { "popular", "alpha", "recent" } do
	http:reset()
	http:queueResponse({ Success = true, StatusCode = 200, Body = "{}" })
	client:browse({ type = "genre", name = "jazz", sort = sortMode })
	recorded = http.requests[1]
	assert(recorded.url:find("sort=" .. sortMode, 1, true), "sort=" .. sortMode .. " in query; got " .. recorded.url)
end

-- nil sort omitted from query string (consistent with limit/offset)
http:reset()
http:queueResponse({ Success = true, StatusCode = 200, Body = "{}" })
client:browse({ type = "genre", name = "jazz" })
recorded = http.requests[1]
assert(not recorded.url:find("sort", 1, true), "nil sort should not appear in URL; got " .. recorded.url)
