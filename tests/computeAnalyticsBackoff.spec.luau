--!strict
-- Unit test for the analytics retry backoff math. Pure function, no I/O.
-- Verifies: steady-state interval at 0 failures, doubling per failure,
-- and the 300s cap.

local mockHttp = require("./_harness/mockHttp")
local loadSdk = require("./_harness/loadSdk").loadSdk

local sdk = loadSdk({ http = mockHttp.new() })
local internal = (sdk :: any).__internal
assert(internal, "expected __internal to be exported under _G.__AUDIOSCAPE_TEST")

local computeAnalyticsBackoff = internal.computeAnalyticsBackoff
assert(typeof(computeAnalyticsBackoff) == "function", "expected computeAnalyticsBackoff to be a function")

-- 0 failures → steady-state interval
assert(computeAnalyticsBackoff(0, 30) == 30, "0 failures should return batchInterval")
assert(computeAnalyticsBackoff(0, 60) == 60, "0 failures should return batchInterval (60)")
assert(computeAnalyticsBackoff(-1, 30) == 30, "negative failures are clamped to steady-state")

-- doubling per failure
assert(computeAnalyticsBackoff(1, 30) == 60, "1 failure → 30 * 2")
assert(computeAnalyticsBackoff(2, 30) == 120, "2 failures → 30 * 4")
assert(computeAnalyticsBackoff(3, 30) == 240, "3 failures → 30 * 8")

-- cap at 300s — 30 * 2^4 = 480 → clamped to 300
assert(computeAnalyticsBackoff(4, 30) == 300, "4 failures clamped at 300")
assert(computeAnalyticsBackoff(5, 30) == 300, "5 failures clamped at 300")
assert(computeAnalyticsBackoff(20, 30) == 300, "many failures clamped at 300")

-- different starting interval still respects the cap
assert(computeAnalyticsBackoff(10, 1) == 300, "1s interval × 1024 → clamped")
assert(computeAnalyticsBackoff(2, 100) == 300, "100s interval × 4 → clamped")
