--!strict
-- Unit test for formatError — maps HTTP status + body into user-facing strings.

local mockHttp = require("./_harness/mockHttp")
local loadSdk = require("./_harness/loadSdk").loadSdk

local sdk = loadSdk({ http = mockHttp.new() })
local formatError = (sdk :: any).__internal.formatError

-- 401 is hard-coded; body ignored
assert(formatError(401, "") == "Invalid API key (401)", "401 with empty body")
assert(formatError(401, "any body") == "Invalid API key (401)", "401 ignores body")

-- 429 is hard-coded
assert(formatError(429, "") == "Rate limited — too many requests (429)", "429")

-- 5xx → server error w/ status code
assert(formatError(500, "") == "Server error — try again later (500)", "500")
assert(formatError(503, "") == "Server error — try again later (503)", "503")
assert(formatError(599, "") == "Server error — try again later (599)", "599")

-- 4xx with no decodable body → fallback
assert(formatError(400, "") == "Request failed (400)", "400 with empty body")
assert(formatError(404, "not json") == "Request failed (404)", "404 with non-JSON body")
assert(formatError(418, "{") == "Request failed (418)", "broken JSON should fall back, not throw")

-- 4xx with JSON `error` field → use it
local badRequest = formatError(400, '{"error":"missing field foo"}')
assert(badRequest == "missing field foo (400)", "got: " .. badRequest)

-- 403 with JSON `error` field
local forbidden = formatError(403, '{"error":"key disabled"}')
assert(forbidden == "key disabled (403)", "got: " .. forbidden)

-- decoded JSON without `error` field → fallback
assert(formatError(400, '{"other":"field"}') == "Request failed (400)", "JSON without error field")

-- decoded JSON with non-string `error` → tostring it
local intError = formatError(400, '{"error":42}')
assert(intError == "42 (400)", "got: " .. intError)
