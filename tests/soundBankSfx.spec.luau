--!strict
-- SFX-kind sound banks classify seeds through /v1/sfx/similar (v0.21.0).
-- The music-catalog lookup on /v1/search can't see SFX-only assets, so it
-- reported them unknown; now a 200 from sfxSimilar marks the seed known and
-- doubles as the neighbour fetch, and a 404 falls through to bridging.

local serde = require("@lune/serde")
local mockHttp = require("./_harness/mockHttp")
local loadSdk = require("./_harness/loadSdk").loadSdk

local function similarResponse(ids: { string }): mockHttp.Response
	local tracks = {}
	for _, id in ids do
		table.insert(tracks, { asset_id = id, name = "Neighbour " .. id })
	end
	return {
		Success = true,
		StatusCode = 200,
		Body = serde.encode("json", { tracks = tracks, meta = { total = #tracks, limit = 5, offset = 0 } }),
	}
end

local function newSdk(): (any, any)
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http })
	local AudioScape: any = sdk
	AudioScape.setApiKey("test-key")
	return AudioScape, http
end

-- 1. SFX-only seed: one sfxSimilar call classifies it AND fills the pool.
do
	local AudioScape, http = newSdk()
	http:queueResponse(similarResponse({ "222", "333", "444" }))
	local bank = AudioScape:createSoundBank({ seeds = { impact = "111" }, kind = "sfx", poolSize = 5 })
	local ok, err = bank:resolveAsync()
	assert(ok, "resolve failed: " .. tostring(err))
	assert(#http.requests == 1, "exactly one HTTP call; got " .. #http.requests)
	local recorded = http.requests[1]
	assert(recorded.method == "GET", "sfxSimilar is GET")
	assert(recorded.url:find("/v1/sfx/similar", 1, true), "classified via /v1/sfx/similar; got " .. recorded.url)
	assert(recorded.url:find("asset_id=111", 1, true), "seed is the anchor; got " .. recorded.url)
	assert(not recorded.url:find("/v1/search", 1, true), "no music-catalog lookup for an sfx bank")
	assert(bank.Pools.impact.source == "catalog", "seed known to the SFX catalog; got " .. bank.Pools.impact.source)
	local pool = bank:getPool("impact")
	assert(pool[1] == "111", "extend mode keeps the seed first; got " .. tostring(pool[1]))
	assert(#pool == 4, "seed + 3 neighbours; got " .. #pool)
end

-- 2. sfxSimilar 404 → seed unknown; bridging can't run under Lune, so "none".
do
	local AudioScape, http = newSdk()
	http:queueResponse({ Success = false, StatusCode = 404, Body = serde.encode("json", { error = "asset_id not found" }) })
	local bank = AudioScape:createSoundBank({ seeds = { impact = "999" }, kind = "sfx" })
	local ok, err = bank:resolveAsync()
	assert(ok, "a 404 is a classification, not a failure: " .. tostring(err))
	assert(bank.Pools.impact.source == "none", "unknown seed reports 'none'; got " .. bank.Pools.impact.source)
	local pool = bank:getPool("impact")
	assert(#pool == 1 and pool[1] == "999", "pool falls back to the seed alone")
end

-- 3. Any other sfxSimilar error still surfaces from resolveAsync.
do
	local AudioScape, http = newSdk()
	http:queueResponse({ Success = false, StatusCode = 503, Body = "" })
	local bank = AudioScape:createSoundBank({ seeds = { impact = "111" }, kind = "sfx" })
	local ok, err = bank:resolveAsync()
	assert(not ok and err and err:find("(503)", 1, true), "5xx propagates; got " .. tostring(err))
end

-- 4. Replace mode drops a seed the SFX catalog knows, same as music.
do
	local AudioScape, http = newSdk()
	http:queueResponse(similarResponse({ "222", "333" }))
	local bank = AudioScape:createSoundBank({ seeds = { impact = "111" }, kind = "sfx", mode = "replace" })
	local ok, err = bank:resolveAsync()
	assert(ok, "resolve failed: " .. tostring(err))
	local pool = bank:getPool("impact")
	assert(#pool == 2 and pool[1] == "222", "catalog seed replaced by neighbours; got " .. tostring(pool[1]))
end
