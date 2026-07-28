--!strict
-- Unit tests for AudioScape:checkAssetHealth.
--
-- The interesting behaviour is the merge of two sources: the catalog knows
-- moderation state, and only the engine can say whether an asset the
-- experience can play exists at all. An id the catalog lacks but the engine
-- can describe is private to that experience — the case that decides whether
-- we ask the developer to share it.

local serde = require("@lune/serde")
local mockHttp = require("./_harness/mockHttp")
local loadSdk = require("./_harness/loadSdk").loadSdk

local function healthResponse(assets: { any }): mockHttp.Response
	local counts = { ok = 0, unavailable = 0, not_in_catalog = 0 }
	for _, a in assets do
		if a.status == "ok" then
			counts.ok += 1
		elseif a.status == "not_in_catalog" then
			counts.not_in_catalog += 1
		else
			counts.unavailable += 1
		end
	end
	return {
		Success = true,
		StatusCode = 200,
		Body = serde.encode("json", {
			assets = assets,
			meta = {
				total = #assets,
				ok = counts.ok,
				unavailable = counts.unavailable,
				not_in_catalog = counts.not_in_catalog,
			},
		}),
	}
end

-- Stands in for AssetService. `known` maps asset id -> Title; anything else
-- returns a bare AssetId, exactly as the real API does when Roblox has no
-- metadata either.
local function fakeAssetService(known: { [string]: string })
	local calls = { batches = {} :: { { string } } }
	return {
		GetAudioMetadataAsync = function(_, idList: { string })
			local batch: { string } = {}
			-- The real API returns a bare { AssetId } when Roblox has no
			-- metadata, so the array is deliberately heterogeneous.
			local out: { any } = {}
			for _, contentId in idList do
				local id = string.match(contentId, "%d+") or contentId
				table.insert(batch, id)
				if known[id] then
					table.insert(out, { AssetId = id, Title = known[id], Artist = "Someone", Duration = 100 })
				else
					table.insert(out, { AssetId = id })
				end
			end
			table.insert(calls.batches, batch)
			return out
		end,
	},
		calls
end

local function newSdk(assetService: any?): (any, any)
	local http = mockHttp.new()
	local sdk = loadSdk({ http = http, services = { AssetService = assetService } })
	local AudioScape: any = sdk
	AudioScape.setApiKey("test-key")
	return AudioScape, http
end

local function byId(result: any): { [string]: any }
	local map = {}
	for _, a in result.assets do
		map[a.asset_id] = a
	end
	return map
end

-- 1. Catalog statuses pass straight through
do
	local AudioScape, http = newSdk()
	http:queueResponse(healthResponse({
		{ asset_id = "1", status = "ok", audio_type = "music", name = "Fine" },
		{ asset_id = "2", status = "moderated", audio_type = "music", name = "Gone" },
		{ asset_id = "3", status = "deleted", audio_type = "sfx", name = "Bye" },
		{ asset_id = "4", status = "delisted", audio_type = "music", name = "Hidden" },
	}))

	local result, err = AudioScape:checkAssetHealth({ "1", "2", "3", "4" })
	assert(result and not err, "checkAssetHealth ok; err: " .. tostring(err))

	local m = byId(result)
	assert(m["1"].status == "ok", "ok passes through")
	assert(m["2"].status == "moderated", "moderated passes through")
	assert(m["3"].status == "deleted", "deleted passes through")
	assert(m["4"].status == "delisted", "delisted passes through")
	assert(m["3"].audio_type == "sfx", "audio_type carried")
	assert(result.meta.ok == 1, "meta.ok counts one")
	assert(result.meta.unavailable == 3, "moderated/deleted/delisted all count as unavailable")
	assert(result.meta.private == 0 and result.meta.unknown == 0, "no private/unknown here")
end

-- 2. The whole point: catalog misses it + engine describes it = private
do
	local engine = fakeAssetService({ ["9"] = "My Private Track" })
	local AudioScape, http = newSdk(engine)
	http:queueResponse(healthResponse({
		{ asset_id = "1", status = "ok", audio_type = "music", name = "Fine" },
		{ asset_id = "9", status = "not_in_catalog" },
	}))

	local result = AudioScape:checkAssetHealth({ "1", "9" })
	local m = byId(result)
	assert(m["9"].status == "private", "engine knows it, catalog does not -> private; got " .. m["9"].status)
	assert(m["9"].name == "My Private Track", "the engine's title is surfaced; got " .. tostring(m["9"].name))
	assert(m["1"].status == "ok", "catalog hits are untouched")
	assert(result.meta.private == 1, "meta.private counts it")
end

-- 3. Neither source knows it -> unknown, never a claim we can't evidence
do
	local engine = fakeAssetService({})
	local AudioScape, http = newSdk(engine)
	http:queueResponse(healthResponse({ { asset_id = "404", status = "not_in_catalog" } }))

	local result = AudioScape:checkAssetHealth({ "404" })
	assert(result.assets[1].status == "unknown", "bare AssetId means unknown; got " .. result.assets[1].status)
	assert(result.meta.unknown == 1 and result.meta.private == 0, "counted as unknown, not private")
end

-- 4. No engine at all: degrade to unknown rather than failing the call
do
	local AudioScape, http = newSdk(nil)
	http:queueResponse(healthResponse({ { asset_id = "9", status = "not_in_catalog" } }))

	local result, err = AudioScape:checkAssetHealth({ "9" })
	assert(result and not err, "a missing AssetService must not fail the call; err: " .. tostring(err))
	assert(result.assets[1].status == "unknown", "degrades to unknown without the engine")
end

-- 5. Only catalog misses go to the engine — asking about everything would burn
--    the 30-per-call metadata budget for no new information.
do
	local engine, calls = fakeAssetService({ ["9"] = "Private" })
	local AudioScape, http = newSdk(engine)
	http:queueResponse(healthResponse({
		{ asset_id = "1", status = "ok" },
		{ asset_id = "2", status = "moderated" },
		{ asset_id = "9", status = "not_in_catalog" },
	}))

	AudioScape:checkAssetHealth({ "1", "2", "9" })
	assert(#calls.batches == 1, "one metadata call; got " .. tostring(#calls.batches))
	local batch = calls.batches[1]
	assert(#batch == 1 and batch[1] == "9", "only the not_in_catalog id was asked about")
end

-- 6. Metadata batches respect the engine's 30-id cap
do
	local known: { [string]: string } = {}
	local ids: { string } = {}
	local assets: { any } = {}
	for i = 1, 65 do
		local id = tostring(1000 + i)
		known[id] = "Track " .. id
		table.insert(ids, id)
		table.insert(assets, { asset_id = id, status = "not_in_catalog" })
	end

	local engine, calls = fakeAssetService(known)
	local AudioScape, http = newSdk(engine)
	http:queueResponse(healthResponse(assets))

	local result = AudioScape:checkAssetHealth(ids)
	assert(#calls.batches == 3, "65 ids -> 3 metadata calls of <=30; got " .. tostring(#calls.batches))
	for i, batch in calls.batches do
		assert(#batch <= 30, "batch " .. tostring(i) .. " exceeded 30: " .. tostring(#batch))
	end
	assert(result.meta.private == 65, "all 65 resolved private; got " .. tostring(result.meta.private))
end

-- 7. Catalog lookups batch at 100 (the asset_ids cap on /v1/search)
do
	local ids: { string } = {}
	for i = 1, 150 do
		table.insert(ids, tostring(2000 + i))
	end

	local AudioScape, http = newSdk()
	local first: { any } = {}
	local second: { any } = {}
	for i = 1, 100 do
		table.insert(first, { asset_id = ids[i], status = "ok" })
	end
	for i = 101, 150 do
		table.insert(second, { asset_id = ids[i], status = "ok" })
	end
	http:queueResponse(healthResponse(first))
	http:queueResponse(healthResponse(second))

	local result = AudioScape:checkAssetHealth(ids)
	assert(#http.requests == 2, "150 ids -> 2 health calls; got " .. tostring(#http.requests))
	assert(result.meta.total == 150, "all 150 reported; got " .. tostring(result.meta.total))
end

-- 8. Input handling: content ids, duplicates, and rejects
do
	local AudioScape, http = newSdk()
	http:queueResponse(healthResponse({ { asset_id = "77", status = "ok" } }))

	local result = AudioScape:checkAssetHealth({ "rbxassetid://77", "77" })
	assert(result.meta.total == 1, "duplicates collapse; got " .. tostring(result.meta.total))

	local decoded: any = serde.decode("json", http.requests[1].body)
	assert(decoded.asset_ids[1] == "77", "content id normalised to the bare id")

	local r2, e2 = AudioScape:checkAssetHealth({})
	assert(r2 == nil and e2, "empty input rejected pre-flight")

	local r3, e3 = AudioScape:checkAssetHealth({ "not-an-id" })
	assert(r3 == nil and e3, "input with no usable ids rejected")
	assert(tostring(e3):find("usable", 1, true), "error explains why; got: " .. tostring(e3))
end

-- 9. reportPrivate is off by default. The result is a list of the developer's
--    private catalog; inferring consent from a diagnostic call isn't right.
do
	local engine = fakeAssetService({ ["9"] = "Private" })
	local AudioScape, http = newSdk(engine)
	http:queueResponse(healthResponse({ { asset_id = "9", status = "not_in_catalog" } }))

	local result = AudioScape:checkAssetHealth({ "9" })
	assert(result.meta.private == 1, "still detected and returned to the caller")
	assert(#http.requests == 1, "no report sent without opting in; got " .. tostring(#http.requests))
end

-- 10. Opting in reports the private assets, with the engine's duration
do
	local engine = fakeAssetService({ ["9"] = "Private Track" })
	local AudioScape, http = newSdk(engine)
	http:queueResponse(healthResponse({
		{ asset_id = "1", status = "ok" },
		{ asset_id = "9", status = "not_in_catalog" },
	}))
	http:queueResponse({ Success = true, StatusCode = 200, Body = '{"accepted":1}' })

	AudioScape:checkAssetHealth({ "1", "9" }, { reportPrivate = true })
	assert(#http.requests == 2, "a report was sent; got " .. tostring(#http.requests))

	local recorded = http.requests[2]
	assert(recorded.url:find("/v1/assets/private-report", 1, true), "hit the report endpoint")

	local decoded: any = serde.decode("json", recorded.body)
	assert(#decoded.assets == 1, "only private assets are reported; got " .. tostring(#decoded.assets))
	assert(decoded.assets[1].asset_id == "9", "the private id")
	assert(decoded.assets[1].title == "Private Track", "the engine's title")
	assert(decoded.assets[1].duration == 100, "the engine's duration, not the uploader's")
end

-- 11. Nothing private → nothing reported, even when opted in
do
	local AudioScape, http = newSdk()
	http:queueResponse(healthResponse({ { asset_id = "1", status = "ok" } }))

	AudioScape:checkAssetHealth({ "1" }, { reportPrivate = true })
	assert(#http.requests == 1, "no empty report sent; got " .. tostring(#http.requests))
end

-- 12. A failed report must not fail a health check the caller already has an
--     answer for.
do
	local engine = fakeAssetService({ ["9"] = "Private" })
	local AudioScape, http = newSdk(engine)
	http:queueResponse(healthResponse({ { asset_id = "9", status = "not_in_catalog" } }))
	http:queueResponse({ Success = false, StatusCode = 500, Body = "" })

	local result, err = AudioScape:checkAssetHealth({ "9" }, { reportPrivate = true })
	assert(result and not err, "health result still returned; err: " .. tostring(err))
	assert(result.assets[1].status == "private", "and the determination is intact")
end

-- 13. A failed health request fails the call rather than reporting everything
--    as unknown, which would look like a definitive answer.
do
	local AudioScape, http = newSdk()
	http:queueResponse({ Success = false, StatusCode = 500, Body = "" })

	local result, err = AudioScape:checkAssetHealth({ "1" })
	assert(result == nil and err, "a failed lookup fails the call")
	assert(tostring(err):find("Server error", 1, true), "surfaces the underlying error; got: " .. tostring(err))
end
