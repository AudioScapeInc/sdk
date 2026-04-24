--!strict
-- Unit test for the POST request() helper, exercised via client:search.
-- Covers happy path, network failure, non-2xx, and JSON decode failure.

local serde = require("@lune/serde")
local mockHttp = require("./_harness/mockHttp")
local loadSdk = require("./_harness/loadSdk").loadSdk

local http = mockHttp.new()
local sdk = loadSdk({ http = http })
local client = (sdk :: any).new("test-key")

-- happy path
http:queueResponse({
	Success = true,
	StatusCode = 200,
	Body = serde.encode("json", { tracks = {}, artists = {}, albums = {}, meta = { total = 0 } }),
})

local result, err = client:search({ query = "ambient", limit = 10 })
assert(result and not err, "search happy path should succeed; err: " .. tostring(err))
assert(result.meta.total == 0, "decoded meta.total")
assert(#http.requests == 1, "exactly one HTTP call expected")

local recorded = http.requests[1]
assert(recorded.method == "POST", "search uses POST, got " .. recorded.method)
assert(recorded.url:find("/v1/search", 1, true), "URL should contain /v1/search; got " .. recorded.url)
assert(recorded.headers and recorded.headers["x-api-key"] == "test-key", "x-api-key header set")
assert(recorded.headers["Content-Type"] == "application/json", "JSON content-type set")
local sentBody = serde.decode("json", recorded.body)
assert(sentBody.query == "ambient", "request body carries query field")
assert(sentBody.limit == 10, "request body carries limit field")

-- network failure
http:reset()
http:queueError("DNS failure")
result, err = client:search({ query = "x" })
assert(result == nil, "network failure returns nil result")
assert(err and err:find("Network error", 1, true), "err should mention Network error; got: " .. tostring(err))
http.error = nil

-- Each error scenario in its own `do` block — luau-lsp narrows `err` to a
-- specific literal across literal-equality asserts and won't broaden across
-- the next reassignment without a fresh local.
do
	-- non-2xx (404 with error body) — uses formatError JSON path
	http:reset()
	http:queueResponse({
		Success = false,
		StatusCode = 404,
		Body = '{"error":"playlist not found"}',
	})
	local r, e = client:search({ query = "x" })
	assert(r == nil, "non-2xx returns nil result")
	assert(e == "playlist not found (404)", "got: " .. tostring(e))
end

do
	-- non-2xx with 401 → hard-coded message
	http:reset()
	http:queueResponse({ Success = false, StatusCode = 401, Body = "" })
	local r, e = client:search({ query = "x" })
	assert(r == nil and e == "Invalid API key (401)", "got: " .. tostring(e))
end

do
	-- decode failure on success (malformed JSON body despite Success=true)
	http:reset()
	http:queueResponse({ Success = true, StatusCode = 200, Body = "not json" })
	local r, e = client:search({ query = "x" })
	assert(r == nil, "malformed body returns nil")
	assert(e == "Failed to decode response", "got: " .. tostring(e))
end

do
	-- pre-flight validation: empty query rejected without HTTP
	http:reset()
	local r, e = client:search({ query = "" })
	assert(r == nil and e and e:find("non-empty query", 1, true), "empty query rejected")
	assert(#http.requests == 0, "no HTTP call for invalid input")
end
