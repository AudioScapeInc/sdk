--!strict
-- Unit test for analytics flush — happy path, 429 + 5xx requeue, 4xx drop,
-- network failure requeue. AudioScape.flushAnalytics retries up to 3 times
-- per call before giving up.

local serde = require("@lune/serde")
local mockHttp = require("./_harness/mockHttp")
local loadSdk = require("./_harness/loadSdk").loadSdk

local function freshClient()
	local http = mockHttp.new()
	-- silent=true: SDK's `warn(...)` calls during error scenarios get captured
	-- to an in-memory list instead of printed. Keeps test output clean while
	-- still exercising the warn path. Captured warnings are returned but we
	-- don't assert on them here — behavior assertions cover the contract.
	local sdk, warnings = loadSdk({ http = http, silent = true })
	local client = (sdk :: any).new("test-key")
	-- prime three events so flush actually does work
	client:trackPlay("asset-a", 1, 60)
	client:trackPlay("asset-b", 2, 30)
	client:trackPlay("asset-c", 3, 15)
	return client, http, warnings
end

-- happy path: one HTTP call, buffer drained, no warnings
do
	local client, http, warnings = freshClient()
	assert(#client._analyticsBuffer == 3, "primed 3 events")

	http:queueResponse({ Success = true, StatusCode = 200, Body = "{}" })
	client:flushAnalytics()

	assert(#http.requests == 1, "happy flush issues one HTTP call, got " .. #http.requests)
	assert(#client._analyticsBuffer == 0, "buffer drained, got " .. #client._analyticsBuffer)
	assert(#warnings == 0, "happy path should produce no warnings, got " .. #warnings)

	local sent = serde.decode("json", http.requests[1].body)
	assert(#sent.events == 3, "all 3 events in batch, got " .. #sent.events)
	assert(sent.events[1].asset_id == "asset-a", "events preserve order")
end

-- 4xx (non-retryable) → batch dropped, buffer empty, single HTTP call, one warn
do
	local client, http, warnings = freshClient()
	http:queueResponse({ Success = false, StatusCode = 400, Body = '{"error":"bad event"}' })
	client:flushAnalytics()

	assert(#http.requests == 1, "4xx → single HTTP call (no retry); got " .. #http.requests)
	assert(#client._analyticsBuffer == 0, "4xx drops the batch (no requeue), got " .. #client._analyticsBuffer)
	assert(#warnings == 1, "4xx logs one warn; got " .. #warnings)
	assert(warnings[1]:find("400", 1, true), "warn mentions status 400; got: " .. warnings[1])
end

-- 429 (retryable) → requeue, retry up to 3 times, three warns
do
	local client, http, warnings = freshClient()
	for _ = 1, 3 do
		http:queueResponse({ Success = false, StatusCode = 429, Body = "" })
	end
	client:flushAnalytics()

	assert(#http.requests == 3, "429 retries 3 times, got " .. #http.requests)
	assert(#client._analyticsBuffer == 3, "events requeued after 3 failed 429s, got " .. #client._analyticsBuffer)
	assert(#warnings == 3, "429 logs one warn per retry; got " .. #warnings)
end

-- 5xx (retryable) → same retry/requeue behavior as 429
do
	local client, http, warnings = freshClient()
	for _ = 1, 3 do
		http:queueResponse({ Success = false, StatusCode = 503, Body = "" })
	end
	client:flushAnalytics()

	assert(#http.requests == 3, "5xx retries 3 times, got " .. #http.requests)
	assert(#client._analyticsBuffer == 3, "events requeued after 3 failed 5xx, got " .. #client._analyticsBuffer)
	assert(#warnings == 3, "5xx logs one warn per retry; got " .. #warnings)
end

-- network failure (RequestAsync raises) → requeue, retry, buffer preserved
do
	local client, http, warnings = freshClient()
	http:queueError("DNS failure")
	client:flushAnalytics()

	assert(#http.requests == 3, "network failure retries 3 times, got " .. #http.requests)
	assert(#client._analyticsBuffer == 3, "events requeued after network failures")
	assert(#warnings == 3, "network failure logs one warn per retry; got " .. #warnings)
	assert(warnings[1]:find("Analytics flush failed", 1, true), "warn mentions failure; got: " .. warnings[1])
end

-- empty buffer is a no-op
do
	local client, http = freshClient()
	-- drain by hand without HTTP
	client._analyticsBuffer = {}
	client:flushAnalytics()
	assert(#http.requests == 0, "empty buffer issues no HTTP, got " .. #http.requests)
end

-- recovery: retryable then success — first call requeues then succeeds on the retry,
-- buffer empty after
do
	local client, http = freshClient()
	http:queueResponse({ Success = false, StatusCode = 503, Body = "" })
	http:queueResponse({ Success = true, StatusCode = 200, Body = "{}" })
	client:flushAnalytics()

	assert(#http.requests == 2, "503 then 200 → 2 HTTP calls, got " .. #http.requests)
	assert(#client._analyticsBuffer == 0, "buffer drained after eventual success")
end
